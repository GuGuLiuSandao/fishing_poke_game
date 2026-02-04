
import asyncio
import threading
import queue
import json
import time
import os
from typing import List, Dict, Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware

from chip_game import ChipGame, Player
from bot_ai import GeneBot
from play_rule import point_value, Hand

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
async def root():
    return {"message": "Diaoyu Game Server Running"}


# --- State Management ---

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []
        self.ws_to_player: Dict[WebSocket, str] = {} # ws -> nickname
        self.player_sessions: Dict[str, WebSocket] = {} # nickname -> current_ws (Persistent Session)

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
        
        # We do NOT remove player_sessions here to allow reconnection.
        # We only remove the reverse mapping (ws -> player) if it exists.
        if websocket in self.ws_to_player:
            player_name = self.ws_to_player[websocket]
            del self.ws_to_player[websocket]
            
            # Optionally mark the session as disconnected in player_sessions, 
            # or just leave the stale WS until overwritten by new login.
            if self.player_sessions.get(player_name) == websocket:
                # self.player_sessions[player_name] = None 
                pass

    def register_player(self, nickname: str, websocket: WebSocket):
        """Associate a nickname with a websocket connection (Login/Reconnect)"""
        # Update session
        self.player_sessions[nickname] = websocket
        self.ws_to_player[websocket] = nickname

    def get_player_ws(self, nickname: str) -> Optional[WebSocket]:
        return self.player_sessions.get(nickname)

    async def broadcast(self, message: dict):
        # We need to sanitize the message for each player if it contains sensitive info
        # Sensitive info: 'players' list where 'hand' is visible.
        # But 'hand' should only be visible to the owner.
        
        # Check if message type needs sanitization
        msg_type = message.get("type")
        needs_sanitization = msg_type in ["round_start", "game_state", "action", "lobby_update", "round_end"] 
        
        data = message.get("data")
        
        # Iterate over a copy to avoid modification during iteration issues
        for connection in list(self.active_connections):
            try:
                # If we need to sanitize
                if needs_sanitization and isinstance(data, dict) and "players" in data:
                    # Identify who this connection belongs to
                    player_name = self.ws_to_player.get(connection)
                    
                    # Sanitize players list
                    sanitized_players = []
                    for p in data["players"]:
                        p_copy = p.copy()
                        # Hide hand if not me
                        if p_copy["name"] != player_name:
                             # Unless it's showdown?
                             if msg_type != "showdown" and msg_type != "game_over" and msg_type != "round_end":
                                 p_copy["hand"] = "[Hidden]"
                        sanitized_players.append(p_copy)
                    
                    # Create new message
                    new_msg = message.copy()
                    new_msg["data"] = data.copy()
                    new_msg["data"]["players"] = sanitized_players
                    
                    await connection.send_text(json.dumps(new_msg))
                else:
                    # No sensitive data, send as is
                    await connection.send_text(json.dumps(message))
            except Exception as e:
                print(f"Broadcast Error: {e}")
                pass
                
    async def send_personal_message(self, websocket: WebSocket, message: dict):
        try:
            await websocket.send_text(json.dumps(message))
        except:
            pass
            
    async def send_to_player(self, nickname: str, message: dict):
        ws = self.get_player_ws(nickname)
        if ws:
            try:
                await ws.send_text(json.dumps(message))
            except:
                pass

manager = ConnectionManager()

# --- Lobby System ---

class Lobby:
    def __init__(self):
        # Seats: index 0-5. Value is dict or None
        # { "type": "human", "name": "Nick", "ws": websocket }
        # { "type": "bot", "name": "Lv1_Rookie", "bot_type": "Lv1" }
        self.seats = [None] * 6 
        self.game_started = False
    
    def sit(self, seat_index, name, ws):
        if 0 <= seat_index < 6 and self.seats[seat_index] is None:
            # Check if player is already seated elsewhere
            for i, seat in enumerate(self.seats):
                if seat and seat.get("ws") == ws:
                    self.seats[i] = None # Stand up from old seat
            
            self.seats[seat_index] = {"type": "human", "name": name, "ws": ws, "status": "online"}
            return True
        return False

    def mark_offline(self, ws):
        changed = False
        for seat in self.seats:
            if seat and seat.get("ws") == ws:
                seat["status"] = "offline"
                seat["ws"] = None
                changed = True
        return changed

    def mark_online(self, name, ws):
        for seat in self.seats:
            if seat and seat.get("name") == name:
                seat["status"] = "online"
                seat["ws"] = ws
                return True
        return False

    def stand_up(self, ws):
        changed = False
        for i, seat in enumerate(self.seats):
            if seat and seat.get("ws") == ws:
                self.seats[i] = None
                changed = True
        return changed

    def add_bot(self, seat_index, bot_type):
        if 0 <= seat_index < 6 and self.seats[seat_index] is None:
            name = f"{bot_type}_{seat_index+1}" # e.g. Lv1_2
            self.seats[seat_index] = {"type": "bot", "name": name, "bot_type": bot_type, "status": "online"}
            return True
        return False

    def remove_bot(self, seat_index):
        if 0 <= seat_index < 6 and self.seats[seat_index] and self.seats[seat_index]["type"] == "bot":
            self.seats[seat_index] = None
            return True
        return False

    def get_state(self):
        # Return serializable state
        serializable_seats = []
        for seat in self.seats:
            if seat is None:
                serializable_seats.append(None)
            else:
                s = seat.copy()
                if "ws" in s:
                    del s["ws"] # Don't serialize websocket
                serializable_seats.append(s)
        return {
            "game_started": self.game_started,
            "seats": serializable_seats
        }

lobby = Lobby()

# --- Game Components ---

class HumanProxy:
    def __init__(self, name, input_queue, connection_manager):
        self.name = name
        self.input_queue = input_queue # Private queue for this player
        self.connection_manager = connection_manager
        
    def action_provider(self, player, phase, pot, game):
        # Notify all users about whose turn it is
        asyncio.run_coroutine_threadsafe(
            self.connection_manager.broadcast({
                "type": "turn_change",
                "data": {"current_player": player.name}
            }),
            loop
        )

        # Notify UI that action is needed
        msg = {
            "type": "request_action",
            "data": {
                "player": player.name,
                "phase": phase,
                "pot": pot,
                "chips": player.chips,
                "hand": str(player.hand),
                "hand_pts": point_value(player.hand) if player.hand else 0,
                "any_bet": game.any_bet
            }
        }
        
        # Find WS dynamically to handle reconnection
        ws = None
        for seat in lobby.seats:
            if seat and seat.get("name") == self.name and seat.get("type") == "human":
                ws = seat.get("ws")
                break

        # If we have a direct WS connection, send it there
        if ws:
            asyncio.run_coroutine_threadsafe(
                self.connection_manager.send_personal_message(ws, msg),
                loop
            )
        else:
            print(f"[HumanProxy] Player {self.name} not found in lobby (disconnected?). Waiting for reconnect...")
            # We still wait on the queue. If they reconnect and send action, it will be routed here.
            # But they need to receive the request first.
            # If they reconnect, they might need a "state sync" or "re-request action".
            # For now, let's assume if they are not here, we just print and wait.
            # When they reconnect and sit, we might need to resend the pending request?
            # That's complex. Simple fix: User has to guess or we rely on "round_start" or subsequent updates?
            # Actually, if they miss the "request_action", they are stuck.
            # We should probably keep trying to send it or have a mechanism to "resend pending request" on Sit.
            pass

        # Block until action received in OUR queue
        print(f"[HumanProxy] Waiting for action for {player.name}...")
        action_data = self.input_queue.get() # Blocking
        print(f"[HumanProxy] Received action for {player.name}: {action_data}")
        
        action = action_data.get("action")
        if action:
            action = action.lower()
            
        if action == "stop":
            raise RuntimeError("Game Stopped")
            
        amount = int(action_data.get("amount", 0))
        return action, amount

class GameManager:
    def __init__(self):
        self.game = None
        self.thread = None
        self.player_queues = {} # name -> queue
        self.ready_event = threading.Event()
        self.running = False
        self.state = "idle" # idle, playing, waiting
        self.msg_queue = queue.Queue()

    def observer(self, event_type, data):
        # Mask hands for other players in round_start
        # But we need to be careful: We want to send EACH player their OWN hand.
        # The current 'broadcast' sends the SAME message to everyone.
        # Ideally, we should filter at the ConnectionManager level or send individual messages.
        # For now, let's keep the simple broadcast but maybe mask everyone's hand in the public broadcast
        # AND send private messages? 
        # Actually, the current frontend logic expects "round_start" to contain all players.
        # If we want to hide hands, we should send a sanitized version to public, and private versions to players.
        
        # Simplified approach for now: Broadcast everything, frontend hides it (insecure but faster to proto)
        # OR: modify observer to put a "raw" message, and the broadcast worker processes it.
        
        # Let's do the "Mask all hands in public broadcast" approach
        # But wait, HumanProxy sends "request_action" which contains the hand.
        # So the active player will know their hand when it's their turn.
        # But they need to know it at "round_start" too.
        
        # Let's just broadcast everything for now (Trust Client). 
        # Security is not the primary concern for this prototype.
        
        msg = {"type": event_type, "data": data}
        self.msg_queue.put(msg)
        
        if event_type == "turn_change":
            # Add delay for bots to simulate thinking
            if data.get("is_bot", False):
                time.sleep(0.7)
        elif event_type == "action":
            time.sleep(1.0)

    def on_human_request(self, msg):
        # Legacy fallback
        self.msg_queue.put(msg)

    def stop_game(self):
        if self.running:
            self.running = False
            # Unblock all queues
            for q in self.player_queues.values():
                q.put({"action": "STOP"})
            self.ready_event.set()
            lobby.game_started = False
            # Broadcast update
            self.msg_queue.put({"type": "lobby_update", "data": lobby.get_state()})

    def start_game(self, seat_config):
        self.stop_game()
        if self.thread and self.thread.is_alive():
            self.thread.join(timeout=1.0)
            
        self.running = True
        self.ready_event.clear()
        self.player_queues = {} # Reset queues
        self.thread = threading.Thread(target=self._run_loop, args=(seat_config,), daemon=True)
        self.thread.start()
        lobby.game_started = True

    def trigger_next_round(self):
        self.ready_event.set()
    
    def reset_game(self):
        # Just restart with same config? Or go back to lobby?
        # Requirement: "点击结束游戏则筹码重新开始" -> Suggests reset within game OR return to lobby.
        # "Click end game then chips restart" -> Reset game state.
        # But usually "End Game" means go back to lobby.
        # Let's interpret "End Game" as "Stop and return to Lobby".
        self.stop_game()

    def _run_loop(self, seat_config):
        try:
            players = []
            for seat in seat_config:
                if seat is None:
                    continue
                
                name = seat["name"]
                if seat["type"] == "human":
                    # Create queue for this human
                    p_queue = queue.Queue()
                    self.player_queues[name] = p_queue
                    # Pass manager and name instead of ws
                    players.append(HumanProxy(name, manager, p_queue, self.on_human_request))
                else:
                    players.append(GeneBot(name, seat.get("bot_type", "Lv1")))

            if len(players) < 2:
                print("Not enough players to start.")
                self.stop_game()
                return

            self.game = ChipGame(players, starting_chips=200, observer=self.observer)
            
            # Broadcast initial game start
            self.msg_queue.put({"type": "game_start", "data": {}})

            round_count = 0
            while self.running:
                round_count += 1
                
                # Check for active players (non-bankrupt)
                active = [p for p in self.game.players if p.chips > 0]
                if len(active) < 2:
                    winner = active[0].name if active else "No one"
                    self.msg_queue.put({"type": "game_over", "data": f"Game Over! Winner: {winner}"})
                    self.state = "idle"
                    break

                self.state = "playing"
                self.game.play_round(log_actions=False)
                
                if self.running:
                    self.state = "waiting"
                    self.msg_queue.put({"type": "wait_ready", "data": {}})
                    self.ready_event.wait()
                    self.state = "playing"
                    self.ready_event.clear()
                
        except RuntimeError:
            pass
        except Exception as e:
            print(f"Game Loop Error: {e}")
            import traceback
            traceback.print_exc()
        finally:
            self.running = False
            # If loop exits naturally (game over), we should update lobby state
            lobby.game_started = False
            self.msg_queue.put({"type": "lobby_update", "data": lobby.get_state()})

    def process_action(self, action_data):
        # action_data: { "action": "...", "amount": ..., "player": "..." }
        player_name = action_data.get("player") # Frontend must send this!
        if player_name and player_name in self.player_queues:
            self.player_queues[player_name].put(action_data)
        else:
            print(f"Unknown player for action: {player_name}")

game_manager = GameManager()

# --- Background Worker ---
# We need the loop to schedule async tasks from thread
loop = None 

async def broadcast_worker():
    global loop
    loop = asyncio.get_running_loop()
    while True:
        # Check game messages
        try:
            # Non-blocking get
            msg = game_manager.msg_queue.get_nowait()
            await manager.broadcast(msg)
        except queue.Empty:
            await asyncio.sleep(0.05)

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(broadcast_worker())

# --- API Endpoints ---

@app.get("/")
async def get():
    return HTMLResponse(open("../web_client/index.html", encoding='utf-8').read())

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        # Send initial lobby state
        await websocket.send_text(json.dumps({
            "type": "lobby_update", 
            "data": lobby.get_state()
        }))

        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)
            msg_type = msg.get("type")
            
            if msg_type == "login":
                nickname = msg.get("nickname")
                if nickname:
                    manager.register_player(nickname, websocket)
                    
                    # Check if player is already seated (Reconnect logic)
                    # We must update the websocket in the lobby seat so HumanProxy can find it
                    if lobby.mark_online(nickname, websocket):
                        print(f"Player {nickname} reconnected to seat")
                    
                    # Re-send lobby state
                    await manager.send_personal_message(websocket, {"type": "lobby_update", "data": lobby.get_state()})
                    
                    # If game is running, restore state
                    if lobby.game_started and game_manager.game:
                        state = game_manager.game.get_player_state(nickname)
                        
                        # 1. Restore Table View (Cards, Chips, Pot)
                        await manager.send_personal_message(websocket, {
                            "type": "round_start",
                            "data": state
                        })

                        if game_manager.state == "waiting":
                             # If waiting for next round, show Ready button
                             await manager.send_personal_message(websocket, {"type": "wait_ready", "data": {}})
                        
                        # 2. If it's my turn AND we are playing, restore Action Buttons
                        elif state.get("is_my_turn"):
                            me = next((p for p in state["players"] if p["name"] == nickname), None)
                            if me:
                                phase = "initial" if not me["has_bet"] else "follow"
                                req_data = {
                                    "player": nickname,
                                    "phase": phase,
                                    "pot": state["pot"],
                                    "any_bet": state["any_bet"],
                                    "chips": me["chips"]
                                }
                                await manager.send_personal_message(websocket, {
                                    "type": "request_action",
                                    "data": req_data
                                })
                
            elif msg_type == "sit":
                seat_idx = msg.get("seat_index")
                nickname = manager.ws_to_player.get(websocket)
                # Fallback to payload nickname if not in session map
                if not nickname:
                    nickname = msg.get("nickname")
                    if nickname:
                        manager.ws_to_player[websocket] = nickname
                
                if nickname:
                    if lobby.sit(seat_idx, nickname, websocket):
                        await manager.broadcast({"type": "lobby_update", "data": lobby.get_state()})
            
            elif msg_type == "stand":
                if lobby.stand_up(websocket):
                    await manager.broadcast({"type": "lobby_update", "data": lobby.get_state()})

            elif msg_type == "add_bot":
                # Permission Check
                player_name = manager.ws_to_player.get(websocket)
                if player_name != "gugu":
                    # Optionally send error message
                    continue

                seat_idx = msg.get("seat_index")
                bot_type = msg.get("bot_type", "Lv1")
                if lobby.add_bot(seat_idx, bot_type):
                    await manager.broadcast({"type": "lobby_update", "data": lobby.get_state()})

            elif msg_type == "remove_bot":
                # Permission Check
                player_name = manager.ws_to_player.get(websocket)
                if player_name != "gugu":
                    continue

                seat_idx = msg.get("seat_index")
                if lobby.remove_bot(seat_idx):
                    await manager.broadcast({"type": "lobby_update", "data": lobby.get_state()})

            elif msg_type == "start_game":
                # Permission Check
                player_name = manager.ws_to_player.get(websocket)
                if player_name != "gugu":
                    continue

                # Only allow if enough players
                # And maybe only if user is seated?
                game_manager.start_game(lobby.seats)
                await manager.broadcast({"type": "lobby_update", "data": lobby.get_state()})

            elif msg_type == "reset_game":
                # Permission Check
                player_name = manager.ws_to_player.get(websocket)
                if player_name != "gugu":
                    continue
                    
                game_manager.reset_game()
                # Reset game implies stopping and maybe clearing chips or restarting?
                # "筹码重新开始" -> Restart with initial chips.
                # If we use start_game(lobby.seats), it re-inits players with 200 chips.
                # So basically same as start_game but maybe triggered from Game UI.
                
            elif msg_type == "action":
                # Frontend must inject player name if not present?
                # Better: Server knows who sent it.
                player_name = manager.ws_to_player.get(websocket)
                if player_name:
                    msg["data"]["player"] = player_name
                    game_manager.process_action(msg["data"])
            
            elif msg_type == "next_round":
                game_manager.trigger_next_round()

    except WebSocketDisconnect:
        # Handle disconnect:
        # Mark player as offline but keep seat
        if lobby.mark_offline(websocket):
            await manager.broadcast({"type": "lobby_update", "data": lobby.get_state()})
            
        manager.disconnect(websocket)
        pass

if __name__ == "__main__":
    import uvicorn
    print("Starting server at http://0.0.0.0:8000")
    uvicorn.run(app, host="0.0.0.0", port=8000)
