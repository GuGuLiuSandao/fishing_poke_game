
import asyncio
import threading
import queue
import json
import time
import os
from typing import List

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles

from chip_game import ChipGame, Player
from bot_ai import GeneBot
from play_rule import point_value, Hand

app = FastAPI()

# --- State Management ---

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        txt = json.dumps(message)
        for connection in self.active_connections:
            try:
                await connection.send_text(txt)
            except:
                pass

manager = ConnectionManager()

# --- Game Components ---

class HumanProxy:
    def __init__(self, name, input_queue):
        self.name = name
        self.input_queue = input_queue
        
    def action_provider(self, player, phase, pot, game):
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
        # We need to send this to WS. Since we are in a sync thread, we can't await.
        # We'll put it in an event queue or use run_coroutine_threadsafe if we had the loop.
        # But easier: direct call to a global helper that pushes to a broadcast queue?
        # Let's use a callback in GameManager.
        if hasattr(self, 'on_request'):
            self.on_request(msg)
            
        # Block until input received
        print(f"[HumanProxy] Waiting for action for {player.name}...")
        action_data = self.input_queue.get() # Blocking
        print(f"[HumanProxy] Received action: {action_data}")
        
        action = action_data.get("action")
        if action == "STOP":
            # Throw exception to exit game loop
            raise RuntimeError("Game Stopped")
            
        amount = int(action_data.get("amount", 0))
        return action, amount

class GameManager:
    def __init__(self):
        self.game = None
        self.thread = None
        self.input_queue = queue.Queue()
        self.ready_event = threading.Event() # For next round synchronization
        self.running = False
        self.msg_queue = queue.Queue() # Queue for messages to be broadcasted
        
    def observer(self, event_type, data):
        # Mask hands for other players in round_start
        if event_type == "round_start":
            for p in data["players"]:
                if p["name"] != "Human":
                    p["hand"] = "[Hidden]"
        
        # Called from Game Thread
        msg = {"type": event_type, "data": data}
        self.msg_queue.put(msg)
        
        # Add delay after each action for pacing
        if event_type == "action":
            time.sleep(1.0)

    def on_human_request(self, msg):
        self.msg_queue.put(msg)

    def stop_game(self):
        if self.running:
            self.running = False
            # Unblock any waiting input
            self.input_queue.put({"action": "STOP"})
            self.ready_event.set() # Unblock ready wait
            print("Game stopped by user request.")
        
    def start_game(self):
        # Ensure previous game is stopped
        self.stop_game()
        # Wait a bit for thread to die (optional but safer)
        if self.thread and self.thread.is_alive():
            self.thread.join(timeout=1.0)
            
        self.running = True
        self.ready_event.clear()
        self.thread = threading.Thread(target=self._run_loop, daemon=True)
        self.thread.start()
        
    def trigger_next_round(self):
        self.ready_event.set()

    def _run_loop(self):
        try:
            # Setup Game
            human = Player("Human", 200, is_bot=False)
            human_proxy = HumanProxy("Human", self.input_queue)
            human.action_provider = human_proxy.action_provider
            human_proxy.on_request = self.on_human_request
            
            bots = [
                Player("Lv1_Rookie", 200, is_bot=True, bot=GeneBot(preset_name="Rookie")),
                Player("Lv2_Casual", 200, is_bot=True, bot=GeneBot(preset_name="Casual")),
                Player("Lv3_Grinder", 200, is_bot=True, bot=GeneBot(preset_name="Grinder"))
            ]
            
            self.game = ChipGame([human] + bots, starting_chips=200, observer=self.observer)
            
            round_count = 0
            while self.running:
                round_count += 1
                # Check bankruptcy
                if human.chips <= 0:
                    self.msg_queue.put({"type": "game_over", "data": "You went bankrupt!"})
                    break
                
                # Play Round
                self.game.play_round(log_actions=False) # Logging handled by observer
                
                # Wait for user to be ready for next round
                if self.running:
                    self.msg_queue.put({"type": "wait_ready", "data": {}})
                    self.ready_event.wait()
                    self.ready_event.clear()
                
        except RuntimeError as e:
            print(f"Game Loop Terminated: {e}")
        except Exception as e:
            print(f"Game Loop Error: {e}")
        finally:
            self.running = False

    def process_action(self, action_data):
        self.input_queue.put(action_data)

game_manager = GameManager()

# --- Background Task to Broadcast Messages ---

async def broadcast_worker():
    while True:
        try:
            # Non-blocking get
            msg = game_manager.msg_queue.get_nowait()
            await manager.broadcast(msg)
        except queue.Empty:
            await asyncio.sleep(0.1)
        except Exception as e:
            print(f"Broadcast error: {e}")

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(broadcast_worker())

# --- API Endpoints ---

@app.get("/")
async def get():
    return HTMLResponse(open("web_client/index.html", encoding='utf-8').read())

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)
            if msg["type"] == "start_game":
                game_manager.start_game()
            elif msg["type"] == "action":
                game_manager.process_action(msg["data"])
            elif msg["type"] == "next_round":
                game_manager.trigger_next_round()
    except WebSocketDisconnect:
        manager.disconnect(websocket)
        game_manager.stop_game()

# Mount static files if needed
# app.mount("/static", StaticFiles(directory="web_client"), name="static")

if __name__ == "__main__":
    import uvicorn
    # Ensure directory exists
    if not os.path.exists("web_client"):
        os.makedirs("web_client")
        
    print("Starting server at http://localhost:8000")
    uvicorn.run(app, host="0.0.0.0", port=8000)
