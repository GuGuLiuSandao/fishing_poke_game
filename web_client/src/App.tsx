import React, { useEffect, useState, useRef } from 'react';
import { useGameStore } from './game/gameStore';
import { useWebSocket } from './hooks/useWebSocket';
import PlayerSeat from './components/PlayerSeat';
import SqueezeMode from './components/SqueezeMode';
import { Settings, History as HistoryIcon, XCircle, RotateCcw, Play } from 'lucide-react';

function App() {
    const { 
        players, 
        pot, 
        roundCount, 
        winner, 
        history, 
        isSqueezeEnabled, 
        isWaitingForReady,
        toggleSqueeze 
    } = useGameStore();

    const { isConnected, sendAction, sendStartGame, sendNextRound } = useWebSocket('ws://localhost:8000/ws');
    
    const [showHistory, setShowHistory] = useState(false);
    const [betAmount, setBetAmount] = useState<string>('');
    const [isSqueezeOpen, setIsSqueezeOpen] = useState(false);
    const historyEndRef = useRef<HTMLDivElement>(null);

    // Auto scroll history
    useEffect(() => {
        historyEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }, [history, showHistory]);

    // Find Human player
    const humanPlayer = players.find(p => p.name === 'Human');
    const isMyTurn = humanPlayer?.isTurn;

    // Determine seats mapping
    // We want Human at 'bottom'.
    // Others distributed: Left, Top, Right
    const getPosition = (index: number, total: number, myIndex: number) => {
        // Normalize index relative to me
        // My index is 0 in relative terms
        const relativeIndex = (index - myIndex + total) % total;
        
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

    const myIndex = players.findIndex(p => p.name === 'Human');
    
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
        }
        sendAction(action, amount);
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
                    <div className="text-xs text-gray-400">ROUND</div>
                    <div className="font-bold text-blue-400">#{roundCount}</div>
                </div>
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

                        {/* Start Game Button (if no players yet) */}
                        {players.length === 0 && isConnected && (
                            <button 
                                onClick={sendStartGame}
                                className="mt-8 px-8 py-3 bg-green-600 hover:bg-green-500 text-white font-bold rounded-full shadow-lg transition-all flex items-center gap-2"
                            >
                                <Play className="w-5 h-5" /> 开始游戏
                            </button>
                        )}

                        {/* Next Round Button (Wait Ready) */}
                        {isWaitingForReady && (
                            <button 
                                onClick={sendNextRound}
                                className="mt-8 px-8 py-3 bg-blue-600 hover:bg-blue-500 text-white font-bold rounded-full shadow-lg transition-all flex items-center gap-2 animate-pulse"
                            >
                                <RotateCcw className="w-5 h-5" /> 准备下一局
                            </button>
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

            {/* Action Bar (Bottom) */}
            {isMyTurn && !winner && (
                <div className="absolute bottom-8 left-1/2 -translate-x-1/2 flex items-center gap-4 z-50 bg-black/80 backdrop-blur-md p-4 rounded-2xl border border-white/10 shadow-2xl animate-in slide-in-from-bottom-10 fade-in">
                    
                    {/* Fold */}
                    <button 
                        onClick={() => handleAction('FOLD')}
                        className="px-6 py-3 bg-red-900/50 hover:bg-red-600 border border-red-500/30 rounded-xl font-bold text-red-200 transition-all active:scale-95"
                    >
                        弃牌 (Fold)
                    </button>

                    {/* Check */}
                    <button 
                        onClick={() => handleAction('CHECK')}
                        className="px-6 py-3 bg-gray-700/50 hover:bg-gray-600 border border-gray-500/30 rounded-xl font-bold text-gray-200 transition-all active:scale-95"
                    >
                        过牌 (Check)
                    </button>

                    {/* Bet Input Group */}
                    <div className="flex items-center gap-2 bg-black/40 p-1 rounded-xl border border-white/10">
                        <input 
                            type="number" 
                            value={betAmount}
                            onChange={(e) => setBetAmount(e.target.value)}
                            placeholder="金额"
                            className="w-24 bg-transparent text-center text-xl font-bold text-yellow-400 outline-none placeholder:text-gray-600"
                        />
                        <button 
                            onClick={() => handleAction('BET')}
                            className="px-6 py-2 bg-yellow-600 hover:bg-yellow-500 text-black font-bold rounded-lg shadow-lg transition-all active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed"
                            disabled={!betAmount || parseInt(betAmount) <= 0}
                        >
                            下注 (Bet)
                        </button>
                    </div>

                    {/* All In */}
                    <button 
                        onClick={() => handleAction('ALLIN')}
                        className="px-6 py-3 bg-gradient-to-r from-purple-900 to-pink-900 hover:from-purple-700 hover:to-pink-700 border border-purple-500/30 rounded-xl font-bold text-purple-100 transition-all active:scale-95 shadow-[0_0_15px_rgba(168,85,247,0.3)]"
                    >
                        All In
                    </button>

                </div>
            )}

            {/* History Panel (Right Sidebar) */}
            <div className={`absolute top-0 right-0 h-full w-80 bg-black/90 backdrop-blur-xl border-l border-white/10 transform transition-transform duration-300 z-[60] ${showHistory ? 'translate-x-0' : 'translate-x-full'}`}>
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
