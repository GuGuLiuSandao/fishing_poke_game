
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
        setWaitingForReady,
        setHasBetThisRound,
        setHasPriorBets,
        setCurrentPhase,
        setLobbyState,
        resetGame,
        nickname
    } = useGameStore();

    // Event Handler for Server Messages
    const handleMessage = useCallback((event: MessageEvent) => {
        try {
            const msg = JSON.parse(event.data);
            console.log("WS Received:", msg);

            const { type, data } = msg;

            switch (type) {
                case "lobby_update":
                    setLobbyState(data.seats, data.game_started);
                    if (!data.game_started) {
                        // Ensure we are in lobby mode if game stopped
                        // But we don't want to reset if we just joined?
                        // Actually resetGame clears everything.
                        // If game_started is false, we should be in lobby.
                    }
                    break;

                case "game_start":
                    addHistory("游戏开始！");
                    setWaitingForReady(false);
                    // gameStarted is set via lobby_update usually, but this confirms it.
                    break;
                case "round_start":
                    setRoundCount(data.round);
                    setPlayers(data.players);
                    setPot(data.pot);
                    setWinner(null);
                    setWaitingForReady(false);
                    setHasBetThisRound(false);
                    setHasPriorBets(false);
                    setCurrentPhase(null);
                    addHistory(`--- 第 ${data.round} 局开始 ---`);
                    break;
                case "action":
                    // Someone took an action
                    const pName = data.player;
                    const act = data.action; // 'bet', 'fold', 'check'
                    const amt = data.amount;
                    let desc = "";
                    
                    const actUpper = act.toUpperCase();
                    if (actUpper === "BET") {
                        desc = `下注 ${amt}`;
                        setHasBetThisRound(true);
                        setHasPriorBets(true);
                    }
                    else if (actUpper === "FOLD") desc = "弃牌";
                    else if (actUpper === "CHECK") desc = "过牌";
                    else if (actUpper === "ALLIN") desc = "All In!";
                    else desc = act;
                    
                    addHistory(`${pName}: ${desc}`);
                    
                    if (data.chips !== undefined) {
                        updatePlayer(pName, { 
                            chips: data.chips, 
                            lastAction: desc,
                            folded: actUpper === "FOLD",
                            isTurn: false // Clear turn flag as they acted
                        });
                    }
                    if (data.pot !== undefined) setPot(data.pot);
                    break;
                
                case "turn_change":
                     // Update turn status for all players
                     const activePlayerName = data.current_player;
                     const currentPlayers = useGameStore.getState().players;
                     const updatedPlayers = currentPlayers.map(p => ({
                         ...p,
                         isTurn: p.name === activePlayerName
                     }));
                     setPlayers(updatedPlayers);
                     break;

                case "request_action":
                    // It's my turn!
                    // data: { player: "Human", phase: "...", pot: ..., any_bet: boolean, ... }
                    // Check if it's ME (nickname)
                    const currentNickname = useGameStore.getState().nickname;
                    if (data.player === currentNickname) {
                        updatePlayer(currentNickname, { isTurn: true });
                        if (data.any_bet !== undefined) {
                            setHasBetThisRound(data.any_bet);
                            setHasPriorBets(data.any_bet); // Sync for reconnect scenarios
                        }
                        if (data.phase) {
                            setCurrentPhase(data.phase);
                        }
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
            if (data && data.players) {
                setPlayers(data.players);
            }

        } catch (e) {
            console.error("WS Parse Error:", e);
        }
    }, [setPlayers, setPot, setRoundCount, setWinner, addHistory, updatePlayer, setLobbyState]);

    useEffect(() => {
        ws.current = new WebSocket(url);

        ws.current.onopen = () => {
            console.log("WS Connected");
            setIsConnected(true);
            
            // Auto-reconnect if nickname exists in store or localStorage
            // The store might be empty on refresh, so check logic in App.tsx to hydrate store first
            // But we can also check here if we want to be robust
            const storedNick = localStorage.getItem("diaoyu_nickname");
            if (storedNick) {
                // We send login immediately
                ws.current?.send(JSON.stringify({ type: "login", nickname: storedNick }));
            }
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
            if (nickname) updatePlayer(nickname, { isTurn: false });
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

    const sendLogin = (nick: string) => {
        if (ws.current && ws.current.readyState === WebSocket.OPEN) {
            ws.current.send(JSON.stringify({ type: "login", nickname: nick }));
        }
    }

    const sendSit = (seatIndex: number) => {
        if (ws.current && ws.current.readyState === WebSocket.OPEN) {
            ws.current.send(JSON.stringify({ 
                type: "sit", 
                seat_index: seatIndex,
                nickname: nickname // Redundancy
            }));
        }
    }

    // Auto-login on connect or reconnect
    useEffect(() => {
        if (isConnected && nickname) {
            sendLogin(nickname);
        }
    }, [isConnected, nickname]);

    const sendStand = () => {
        if (ws.current && ws.current.readyState === WebSocket.OPEN) {
            ws.current.send(JSON.stringify({ type: "stand" }));
        }
    }

    const sendAddBot = (seatIndex: number, botType: string) => {
        if (ws.current && ws.current.readyState === WebSocket.OPEN) {
            ws.current.send(JSON.stringify({ type: "add_bot", seat_index: seatIndex, bot_type: botType }));
        }
    }

    const sendRemoveBot = (seatIndex: number) => {
        if (ws.current && ws.current.readyState === WebSocket.OPEN) {
            ws.current.send(JSON.stringify({ type: "remove_bot", seat_index: seatIndex }));
        }
    }

    const sendResetGame = () => {
        if (ws.current && ws.current.readyState === WebSocket.OPEN) {
            ws.current.send(JSON.stringify({ type: "reset_game" }));
            resetGame(); // Also reset local state
        }
    }

    return { 
        isConnected, 
        sendAction, 
        sendStartGame, 
        sendNextRound,
        sendLogin,
        sendSit,
        sendStand,
        sendAddBot,
        sendRemoveBot,
        sendResetGame
    };
};
