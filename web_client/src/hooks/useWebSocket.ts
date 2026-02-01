import { useEffect, useRef, useCallback, useState } from 'react';
import { useGameStore } from '../game/gameStore';

export const useWebSocket = (url: string) => {
    const ws = useRef<WebSocket | null>(null);
    const [isConnected, setIsConnected] = useState(false);
    const { 
        setPlayers, 
        setPot, 
        setRoundCount, 
        setWinner, 
        addHistory,
        updatePlayer,
        setWaitingForReady
    } = useGameStore();

    // Event Handler for Server Messages
    const handleMessage = useCallback((event: MessageEvent) => {
        try {
            const msg = JSON.parse(event.data);
            console.log("WS Received:", msg);

            const { type, data } = msg;

            switch (type) {
                case "game_start":
                    addHistory("游戏开始！");
                    setWaitingForReady(false);
                    break;
                case "round_start":
                    setRoundCount(data.round);
                    setPlayers(data.players);
                    setPot(data.pot);
                    setWinner(null);
                    setWaitingForReady(false);
                    addHistory(`--- 第 ${data.round} 局开始 ---`);
                    break;
                case "action":
                    // Someone took an action
                    const pName = data.player;
                    const act = data.action;
                    const amt = data.amount;
                    let desc = "";
                    if (act === "BET") desc = `下注 ${amt}`;
                    else if (act === "FOLD") desc = "弃牌";
                    else if (act === "CHECK") desc = "过牌";
                    else if (act === "ALLIN") desc = "All In!";
                    else desc = act;
                    
                    addHistory(`${pName}: ${desc}`);
                    
                    // Update this player's state
                    // We assume data.players is the full updated list if provided,
                    // but usually 'action' event might just give delta.
                    // Checking backend: Backend sends full player list in 'round_start', but for 'action'?
                    // Let's check backend implementation later.
                    // Assuming 'action' event might contain updated 'players' list or we update locally.
                    // Current backend sends: {type: 'action', data: {player: 'Human', action: 'BET', amount: 10, chips: 190, pot: 210}}
                    // It gives specific fields.
                    
                    if (data.chips !== undefined) {
                        updatePlayer(pName, { 
                            chips: data.chips, 
                            lastAction: desc,
                            folded: act === "FOLD"
                        });
                    }
                    if (data.pot !== undefined) setPot(data.pot);

                    // Reset turn for everyone, set turn for next?
                    // Backend doesn't explicitly send "turn_change" yet, usually relies on request_action.
                    break;
                
                case "turn_change":
                     // Not implemented in backend yet, but good to have
                     // updatePlayer(data.current_player, { isTurn: true });
                     break;

                case "request_action":
                    // It's my turn!
                    // data: { player: "Human", phase: "...", pot: ..., ... }
                    if (data.player === "Human") {
                        updatePlayer("Human", { isTurn: true });
                        // Trigger UI to show controls (handled by checking isTurn in UI)
                    }
                    break;

                case "showdown":
                    addHistory("--- 摊牌时刻 ---");
                    // Update all hands
                    if (data.players) {
                        setPlayers(data.players);
                    }
                    break;

                case "round_end":
                    setWinner(data.winner);
                    addHistory(`本局赢家: ${data.winner}`);
                    // data.players contains final states
                    if (data.players) setPlayers(data.players);
                    break;
                
                case "game_over":
                    addHistory(`游戏结束: ${data}`);
                    break;

                case "wait_ready":
                    // Show Ready Button
                    setWaitingForReady(true);
                    break;
            }

            // Always update players list if provided in any message
            if (data.players) {
                setPlayers(data.players);
            }

        } catch (e) {
            console.error("WS Parse Error:", e);
        }
    }, [setPlayers, setPot, setRoundCount, setWinner, addHistory, updatePlayer]);

    useEffect(() => {
        ws.current = new WebSocket(url);

        ws.current.onopen = () => {
            console.log("WS Connected");
            setIsConnected(true);
        };

        ws.current.onclose = () => {
            console.log("WS Disconnected");
            setIsConnected(false);
        };

        ws.current.onmessage = handleMessage;

        return () => {
            ws.current?.close();
        };
    }, [url, handleMessage]);

    const sendAction = (action: string, amount: number = 0) => {
        if (ws.current && ws.current.readyState === WebSocket.OPEN) {
            ws.current.send(JSON.stringify({
                type: "action",
                data: { action, amount }
            }));
            // Optimistic update: clear my turn
            updatePlayer("Human", { isTurn: false });
        }
    };

    const sendStartGame = () => {
        if (ws.current && ws.current.readyState === WebSocket.OPEN) {
            ws.current.send(JSON.stringify({ type: "start_game" }));
        }
    };

    const sendNextRound = () => {
        if (ws.current && ws.current.readyState === WebSocket.OPEN) {
            ws.current.send(JSON.stringify({ type: "next_round" }));
        }
    };

    return { isConnected, sendAction, sendStartGame, sendNextRound };
};
