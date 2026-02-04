
import React, { useEffect, useState, useRef } from 'react';
import { useGameStore, type Seat } from './game/gameStore';
import { useWebSocket } from './hooks/useWebSocket';
import PlayerSeat from './components/PlayerSeat';
import SqueezeMode from './components/SqueezeMode';
import { Settings, History as HistoryIcon, XCircle, RotateCcw, Play, Users, LogOut, Plus, Trash2, StopCircle } from 'lucide-react';

// Login Screen Component
const LoginScreen = ({ onLogin }: { onLogin: (name: string) => void }) => {
    const [name, setName] = useState("");
    
    const handleSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        if (name.trim()) {
            onLogin(name.trim());
        }
    };

    return (
        <div className="w-full h-screen bg-[#1a1a1a] flex items-center justify-center text-white">
            <div className="bg-[#2c2c2c] p-8 rounded-2xl shadow-2xl w-96 border border-white/10">
                <h1 className="text-3xl font-bold mb-6 text-center text-yellow-500">钓鱼 (Fishing)</h1>
                <form onSubmit={handleSubmit} className="space-y-4">
                    <div>
                        <label className="block text-gray-400 text-sm font-bold mb-2">请输入昵称</label>
                        <input 
                            type="text" 
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            className="w-full bg-black/50 border border-gray-600 rounded-lg py-3 px-4 text-white focus:outline-none focus:border-yellow-500 transition-colors"
                            placeholder="你的名字..."
                            maxLength={10}
                            autoFocus
                        />
                    </div>
                    <button 
                        type="submit"
                        disabled={!name.trim()}
                        className="w-full bg-yellow-600 hover:bg-yellow-500 disabled:opacity-50 disabled:cursor-not-allowed text-black font-bold py-3 px-4 rounded-lg transition-all transform active:scale-95"
                    >
                        进入大厅
                    </button>
                </form>
            </div>
        </div>
    );
};

// Lobby Screen Component
const LobbyScreen = ({ 
    nickname, 
    seats, 
    onSit, 
    onStand, 
    onAddBot, 
    onRemoveBot, 
    onStartGame 
}: { 
    nickname: string, 
    seats: (Seat | null)[],
    onSit: (idx: number) => void,
    onStand: () => void,
    onAddBot: (idx: number, type: string) => void,
    onRemoveBot: (idx: number) => void,
    onStartGame: () => void
}) => {
    const mySeatIndex = seats.findIndex(s => s && s.type === 'human' && s.name === nickname);
    const isSeated = mySeatIndex !== -1;
    const seatedCount = seats.filter(s => s !== null).length;
    const canStart = seatedCount >= 2;

    return (
        <div className="w-full h-screen bg-[#1a1a1a] flex flex-col items-center justify-center text-white relative overflow-hidden">
             {/* Background Texture */}
             <div className="absolute inset-0 bg-[#2c2c2c] opacity-50 pointer-events-none"></div>

             <div className="z-10 w-full max-w-4xl p-8">
                <div className="flex justify-between items-center mb-8">
                    <h2 className="text-2xl font-bold flex items-center gap-2">
                        <Users className="text-blue-400" /> 游戏大厅
                    </h2>
                    <div className="text-gray-400">欢迎, <span className="text-yellow-400 font-bold">{nickname}</span></div>
                </div>

                {/* Seats Grid (Circle-ish representation) */}
                <div className="relative w-[600px] h-[400px] mx-auto bg-[#35654d] rounded-[100px] border-[10px] border-[#3e2723] shadow-2xl mb-8 flex items-center justify-center">
                    
                    {/* Center Info */}
                    <div className="text-center">
                        <div className="text-yellow-100/50 font-bold tracking-widest mb-2">TABLE</div>
                        {isSeated && (
                            nickname === 'gugu' ? (
                                <button 
                                    onClick={onStartGame}
                                    disabled={!canStart}
                                    className="px-8 py-3 bg-green-600 hover:bg-green-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white font-bold rounded-full shadow-lg transition-all flex items-center gap-2 mx-auto"
                                >
                                    <Play className="w-5 h-5" /> 开始游戏
                                </button>
                            ) : (
                                canStart && <div className="text-gray-400 text-sm mt-2">等待管理员(gugu)开始游戏...</div>
                            )
                        )}
                        {!isSeated && <div className="text-gray-300 text-sm mt-2">请选择座位加入</div>}
                        {isSeated && !canStart && <div className="text-orange-300 text-sm mt-2">等待更多玩家...</div>}
                    </div>

                    {/* Render 6 Seats */}
                    {seats.map((seat, index) => {
                        // Calculate position
                        const angle = (index * 60 - 90) * (Math.PI / 180); // Start from top
                        const radius = 240; // Distance from center
                        const left = 300 + Math.cos(angle) * radius;
                        const top = 200 + Math.sin(angle) * 150; // Ellipse

                        return (
                            <div 
                                key={index}
                                className="absolute w-24 h-24 -ml-12 -mt-12 flex flex-col items-center justify-center transition-all"
                                style={{ left, top }}
                            >
                                {seat ? (
                                    // Occupied Seat
                                    <div className="relative group">
                                        <div className={`w-16 h-16 rounded-full flex items-center justify-center border-4 shadow-lg ${
                                            seat.status === 'offline' ? 'bg-gray-600 border-gray-400' : (
                                                seat.type === 'human' ? 'bg-blue-600 border-blue-400' : 'bg-purple-600 border-purple-400'
                                            )
                                        }`}>
                                            <span className="text-xl font-bold text-white">
                                                {seat.name.slice(0, 2).toUpperCase()}
                                            </span>
                                        </div>
                                        <div className="absolute -bottom-6 w-32 -left-8 text-center text-xs font-bold truncate bg-black/50 rounded px-1">
                                            {seat.name} {seat.status === 'offline' && '(离线)'}
                                        </div>
                                        
                                        {/* Actions for occupied seat */}
                                        {seat.type === 'human' && seat.name === nickname && (
                                            <button 
                                                onClick={onStand}
                                                className="absolute -top-2 -right-2 bg-red-500 hover:bg-red-400 text-white rounded-full p-1 shadow-lg opacity-0 group-hover:opacity-100 transition-opacity"
                                                title="站起"
                                            >
                                                <LogOut size={12} />
                                            </button>
                                        )}
                                        {seat.type === 'bot' && nickname === 'gugu' && (
                                            <button 
                                                onClick={() => onRemoveBot(index)}
                                                className="absolute -top-2 -right-2 bg-red-500 hover:bg-red-400 text-white rounded-full p-1 shadow-lg opacity-0 group-hover:opacity-100 transition-opacity"
                                                title="移除电脑"
                                            >
                                                <Trash2 size={12} />
                                            </button>
                                        )}
                                    </div>
                                ) : (
                                    // Empty Seat
                                    <div className="relative group">
                                        <button 
                                            onClick={() => !isSeated && onSit(index)}
                                            disabled={isSeated}
                                            className={`w-16 h-16 rounded-full border-4 border-dashed border-white/20 flex items-center justify-center transition-all ${!isSeated ? 'hover:bg-white/10 hover:border-yellow-400 cursor-pointer' : 'cursor-default'}`}
                                        >
                                            <span className="text-white/20 text-xs">空位</span>
                                        </button>
                                        
                                        {/* Add Bot Menu (Only if I am 'gugu') */}
                                        {nickname === 'gugu' && (
                                            <div className="absolute top-0 left-0 w-full h-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none">
                                                <div className="absolute -top-12 bg-black/80 rounded-lg p-2 flex flex-col gap-1 z-20 pointer-events-auto">
                                                    <div className="text-xs text-gray-400 text-center mb-1">添加电脑</div>
                                                    <div className="flex gap-1">
                                                        <button onClick={() => onAddBot(index, "Lv1")} className="px-2 py-1 bg-green-700 hover:bg-green-600 rounded text-xs">Lv1</button>
                                                        <button onClick={() => onAddBot(index, "Lv2")} className="px-2 py-1 bg-blue-700 hover:bg-blue-600 rounded text-xs">Lv2</button>
                                                        <button onClick={() => onAddBot(index, "Lv3")} className="px-2 py-1 bg-red-700 hover:bg-red-600 rounded text-xs">Lv3</button>
                                                    </div>
                                                </div>
                                                <div className="bg-white/10 rounded-full p-2 backdrop-blur-sm pointer-events-none">
                                                    <Plus size={20} className="text-yellow-400" />
                                                </div>
                                            </div>
                                        )}
                                    </div>
                                )}
                            </div>
                        );
                    })}
                </div>
            </div>
        </div>
    );
}

function App() {
    // Dynamic WebSocket URL
    const params = new URLSearchParams(window.location.search);
    const overrideWsUrl = params.get('ws');
    const envWsUrl = import.meta.env.VITE_WS_URL;

    // Get uid from URL if present (Auto-login)
    const uid = params.get('uid');

    const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsHost = window.location.hostname;
    // If running on localhost, use port 8000. Otherwise, assume backend is on the same host/port or proxied.
    const wsPort = '8000';
    
    const localWsUrl = `${wsProtocol}//${wsHost}:${wsPort}/ws`;
    const wsUrl = overrideWsUrl || envWsUrl || localWsUrl;

    const { 
        players, 
        pot, 
        roundCount, 
        winner, 
        history, 
        isSqueezeEnabled, 
        isWaitingForReady,
        hasBetThisRound,
        hasPriorBets,
        currentPhase,
        toggleSqueeze,
        // New State
        nickname,
        lobbySeats,
        gameStarted,
        setNickname
    } = useGameStore();

    const { 
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
    } = useWebSocket(wsUrl);
    
    const [showHistory, setShowHistory] = useState(false);
    const [betAmount, setBetAmount] = useState<string>('');
    const [isSqueezeOpen, setIsSqueezeOpen] = useState(false);
    const historyEndRef = useRef<HTMLDivElement>(null);

    // Auto scroll history
    useEffect(() => {
        historyEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }, [history, showHistory]);

    // Restore nickname from localStorage or URL
    useEffect(() => {
        if (uid) {
            // URL param takes precedence
            localStorage.setItem("diaoyu_nickname", uid);
            setNickname(uid);
        } else {
            const stored = localStorage.getItem("diaoyu_nickname");
            if (stored && !nickname) {
                setNickname(stored);
            }
        }
    }, [uid]);

    // Handle Login
    const handleLogin = (name: string) => {
        localStorage.setItem("diaoyu_nickname", name);
        setNickname(name);
        sendLogin(name);
    };

    // If not logged in, show login
    if (!nickname) {
        return <LoginScreen onLogin={handleLogin} />;
    }

    // If game not started, show Lobby
    if (!gameStarted) {
        return <LobbyScreen 
            nickname={nickname}
            seats={lobbySeats}
            onSit={sendSit}
            onStand={sendStand}
            onAddBot={sendAddBot}
            onRemoveBot={sendRemoveBot}
            onStartGame={sendStartGame}
        />;
    }

    // Game Logic
    // Find Human player (Me)
    const humanPlayer = players.find(p => p.name === nickname);
    const isMyTurn = humanPlayer?.isTurn;

    // Determine seats mapping relative to Me
    const getPosition = (index: number, total: number, myIndex: number) => {
        // If I am not in the game (observer?), myIndex might be -1.
        // If observer, just show index 0 at bottom?
        const baseIndex = myIndex === -1 ? 0 : myIndex;
        
        const relativeIndex = (index - baseIndex + total) % total;
        
        if (relativeIndex === 0) return 'bottom';
        if (total === 2) return 'top';
        if (total === 3) {
            if (relativeIndex === 1) return 'top-left'; // or top
            return 'top-right';
        }
        if (total === 4) {
            if (relativeIndex === 1) return 'left';
            if (relativeIndex === 2) return 'top';
            return 'right';
        }
        // Fallback for more players
        const positions = ['bottom', 'left', 'top-left', 'top', 'top-right', 'right', 'bottom-right', 'bottom-left'];
        return positions[relativeIndex] as any;
    };

    const myIndex = players.findIndex(p => p.name === nickname);
    
    // Actions
    const handleAction = (action: string) => {
        let amount = 0;
        if (action === 'BET') {
            const val = parseInt(betAmount);
            if (isNaN(val) || val <= 0) {
                alert("请输入有效的下注金额");
                return;
            }
            amount = val;
        } else if (action === 'DAI' || action === 'CHI') {
            // Dai/Chi matches the pot.
            amount = pot;
            action = 'BET'; // Send BET to backend
        }
        
        sendAction(action.toLowerCase(), amount);
        setBetAmount('');
    };

    // Squeeze Logic
    const handleOpenSqueeze = () => {
        setIsSqueezeOpen(true);
    };

    // Helper to get my cards for squeeze
    const getMyCards = () => {
        if (!humanPlayer || !humanPlayer.hand || humanPlayer.hand === "[Hidden]") return [];
        const handStr = humanPlayer.hand;
        const matches = [...handStr.matchAll(/([♥♦♠♣]?)([^, \[\]♥♦♠♣]+)/g)];
        return matches.map(m => {
            let suit = m[1] || '';
            const name = m[2];
            if (name === '大王') suit = '红';
            return { name, suit };
        });
    };

    return (
        <div className="relative w-full h-screen bg-[#1a1a1a] text-white overflow-hidden font-sans select-none">
            
            {/* Background Texture */}
            <div className="absolute inset-0 bg-[#2c2c2c] opacity-50 pointer-events-none"></div>

            {/* Header Info */}
            <div className="absolute top-4 left-4 z-50 flex gap-4">
                <div className="bg-black/50 backdrop-blur-md px-4 py-2 rounded-lg border border-white/10 shadow-lg">
                    <div className="text-xs text-gray-400">STATUS</div>
                    <div className={`flex items-center gap-2 font-bold ${isConnected ? 'text-green-400' : 'text-red-400'}`}>
                        <div className={`w-2 h-2 rounded-full ${isConnected ? 'bg-green-400' : 'bg-red-400'} animate-pulse`} />
                        {isConnected ? 'Connected' : 'Disconnected'}
                    </div>
                </div>
                
                <div className="bg-black/50 backdrop-blur-md px-4 py-2 rounded-lg border border-white/10 shadow-lg">
                    <div className="text-xs text-gray-400">PLAYER</div>
                    <div className="font-bold text-yellow-500">{nickname}</div>
                </div>

                {/* End Game Button - Only for gugu */}
                {nickname === 'gugu' && (
                    <button 
                        onClick={sendResetGame}
                        className="bg-red-900/80 hover:bg-red-800 text-white px-4 py-2 rounded-lg border border-red-500/30 flex items-center gap-2 transition-all"
                    >
                        <StopCircle size={16} />
                        结束游戏
                    </button>
                )}
            </div>

            {/* Top Right Controls */}
            <div className="absolute top-4 right-4 z-50 flex gap-2">
                <button 
                    onClick={toggleSqueeze}
                    className={`p-2 rounded-lg border transition-all ${isSqueezeEnabled ? 'bg-yellow-500/20 border-yellow-500 text-yellow-500' : 'bg-black/50 border-white/10 text-gray-400 hover:bg-white/10'}`}
                    title="搓牌模式开关"
                >
                    <Settings className="w-5 h-5" />
                </button>
                <button 
                    onClick={() => setShowHistory(!showHistory)}
                    className={`p-2 rounded-lg border transition-all ${showHistory ? 'bg-blue-500/20 border-blue-500 text-blue-500' : 'bg-black/50 border-white/10 text-gray-400 hover:bg-white/10'}`}
                    title="历史记录"
                >
                    <HistoryIcon className="w-5 h-5" />
                </button>
            </div>

            {/* Main Poker Table */}
            <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[90%] h-[70%] max-w-5xl">
                <div className="relative w-full h-full rounded-[100px] border-[15px] border-[#3e2723] bg-[radial-gradient(circle,#35654d_0%,#204030_100%)] shadow-[inset_0_0_100px_rgba(0,0,0,0.6)]">
                    
                    {/* Center Pot */}
                    <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 flex flex-col items-center">
                        <div className="text-yellow-100/50 font-bold tracking-widest text-lg mb-2">POT</div>
                        <div className="bg-black/40 px-6 py-2 rounded-full border border-yellow-500/30 backdrop-blur-sm">
                            <span className="text-3xl text-yellow-400 font-mono font-bold">¥{pot}</span>
                        </div>
                        
                        {/* Winner Announcement */}
                        {winner && (
                            <div className="mt-4 px-6 py-2 bg-yellow-500 text-black font-bold rounded-full shadow-[0_0_20px_rgba(234,179,8,0.6)] animate-bounce">
                                🏆 {winner} Wins!
                            </div>
                        )}
                    </div>

                    {/* Render Seats */}
                    {players.map((player, index) => (
                        <PlayerSeat 
                            key={player.name}
                            player={player}
                            position={getPosition(index, players.length, myIndex)}
                            winner={winner}
                            isSqueezeEnabled={isSqueezeEnabled}
                            onOpenSqueeze={handleOpenSqueeze}
                        />
                    ))}

                </div>
            </div>

            {/* Action Bar (Bottom Right) */}
            {isMyTurn && !winner && (
                <div className="absolute bottom-8 right-8 flex items-center gap-4 z-50 bg-black/80 backdrop-blur-md p-4 rounded-2xl border border-white/10 shadow-2xl animate-in slide-in-from-right-10 fade-in">
                    
                    {currentPhase === 'follow' ? (
                        <>
                            <button 
                                onClick={() => handleAction('CHECK')}
                                className="px-6 py-3 bg-gray-700/50 hover:bg-gray-600 border border-gray-500/30 rounded-xl font-bold text-gray-200 transition-all active:scale-95"
                            >
                                过牌 (Check)
                            </button>

                            <button 
                                onClick={() => handleAction('DAI')}
                                className="px-6 py-3 bg-yellow-600 hover:bg-yellow-500 text-black font-bold rounded-xl shadow-lg transition-all active:scale-95"
                            >
                                带 ¥{pot}
                            </button>
                        </>
                    ) : (
                        <>
                            <button 
                                onClick={() => handleAction('FOLD')}
                                className="px-6 py-3 bg-red-900/50 hover:bg-red-600 border border-red-500/30 rounded-xl font-bold text-red-200 transition-all active:scale-95"
                            >
                                弃牌 (Fold)
                            </button>

                            <div className="flex items-center gap-2 bg-black/40 p-1 rounded-xl border border-white/10">
                                <input 
                                    type="number" 
                                    min="1"
                                    max={pot}
                                    value={betAmount}
                                    onChange={(e) => setBetAmount(e.target.value)}
                                    placeholder={`1-¥${pot}`}
                                    title={`可下注1至当前底池金额¥${pot}`}
                                    className="w-24 bg-transparent text-center text-xl font-bold text-yellow-400 outline-none placeholder:text-gray-600"
                                />
                                <button 
                                    onClick={() => handleAction('BET')}
                                    className="px-6 py-2 bg-yellow-600 hover:bg-yellow-500 text-black font-bold rounded-lg shadow-lg transition-all active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed"
                                    disabled={!betAmount || parseInt(betAmount) <= 0 || parseInt(betAmount) > pot}
                                >
                                    下注 (Bet)
                                </button>
                            </div>

                            <button 
                                onClick={() => handleAction(hasPriorBets ? 'DAI' : 'CHI')}
                                className="px-6 py-3 bg-yellow-600 hover:bg-yellow-500 text-black font-bold rounded-xl shadow-lg transition-all active:scale-95"
                            >
                                {hasPriorBets ? `带 ¥${pot}` : `吃 ¥${pot}`}
                            </button>
                        </>
                    )}

                </div>
            )}

            {/* Next Round Button (Wait Ready) - Moved to Bottom Left */}
            {isWaitingForReady && (
                <div className="absolute bottom-8 left-8 z-50 animate-in slide-in-from-left-10 fade-in">
                    <button 
                        onClick={sendNextRound}
                        className="px-8 py-3 bg-blue-600 hover:bg-blue-500 text-white font-bold rounded-full shadow-lg transition-all flex items-center gap-2 animate-pulse"
                    >
                        <RotateCcw className="w-5 h-5" /> 准备下一局
                    </button>
                </div>
            )}

            {/* History Panel (Right Sidebar) - Fixed to prevent layout shift */}
            <div className={`fixed top-0 right-0 h-full w-80 bg-black/90 backdrop-blur-xl border-l border-white/10 transform transition-transform duration-300 z-[60] ${showHistory ? 'translate-x-0' : 'translate-x-full'}`}>
                <div className="flex items-center justify-between p-4 border-b border-white/10">
                    <div className="font-bold text-lg flex items-center gap-2">
                        <HistoryIcon className="w-5 h-5 text-blue-400" /> 对局记录
                    </div>
                    <button onClick={() => setShowHistory(false)} className="text-gray-400 hover:text-white">
                        <XCircle className="w-6 h-6" />
                    </button>
                </div>
                <div className="p-4 h-[calc(100%-60px)] overflow-y-auto space-y-2 history-scroll">
                    {history.map((entry, idx) => (
                        <div key={idx} className="text-sm text-gray-300 border-b border-white/5 pb-1 mb-1 last:border-0">
                            {entry}
                        </div>
                    ))}
                    <div ref={historyEndRef} />
                </div>
            </div>

            {/* Squeeze Mode Overlay */}
            {isSqueezeOpen && (
                <SqueezeMode 
                    cards={getMyCards()} 
                    onClose={() => setIsSqueezeOpen(false)} 
                />
            )}

        </div>
    );
}

export default App;
