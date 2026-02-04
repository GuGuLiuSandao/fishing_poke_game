import React, { useState } from 'react';
import PlayingCard from './PlayingCard';
import { User, History, Trophy, Eye } from 'lucide-react';

interface Player {
    name: string;
    chips: number;
    folded: boolean;
    hand: string;
    lastAction?: string;
    isTurn?: boolean;
}

interface PlayerSeatProps {
    player: Player;
    position: 'bottom' | 'left' | 'right' | 'top' | 'top-left' | 'top-right' | 'bottom-left' | 'bottom-right';
    winner: string | null;
    isSqueezeEnabled: boolean;
    onOpenSqueeze: () => void;
}

const PlayerSeat: React.FC<PlayerSeatProps> = ({ player, position, winner, isSqueezeEnabled, onOpenSqueeze }) => {
    const [showHistory, setShowHistory] = useState(false);
    const isFolded = player.folded;
    const isWinner = winner === player.name;
    const isTurn = player.isTurn;

    // Position styles
    const positionStyles: Record<string, string> = {
        'bottom': '-bottom-10 left-1/2 -translate-x-1/2',
        'left': 'top-1/2 -left-10 -translate-y-1/2',
        'right': 'top-1/2 -right-10 -translate-y-1/2',
        'top': '-top-10 left-1/2 -translate-x-1/2',
        'top-left': '-top-4 -left-4',
        'top-right': '-top-4 -right-4',
        'bottom-left': '-bottom-4 -left-4',
        'bottom-right': '-bottom-4 -right-4'
    };

    const styleClass = positionStyles[position] || positionStyles.top;

    // Parse Hand
    let cards: Array<{ name: string; suit: string }> = [];
    const handStr = player.hand;

    if (handStr && handStr !== "[Hidden]") {
        // Regex to extract card suit and name (e.g. [♥3, ♦Q])
        // Matches: Group 1 = Suit, Group 2 = Name
        const matches = [...handStr.matchAll(/([♥♦♠♣]?)([^, \[\]♥♦♠♣]+)/g)];
        if (matches.length > 0) {
            cards = matches.map(m => {
                let suit = m[1] || '';
                const name = m[2];
                if (name === '大王') suit = '红';
                return { name, suit };
            });
        }
    }

    // Determine cards to display
    // Logic: If Human (bottom), Squeeze Enabled, Has >= 2 cards, and No Winner yet -> Hide 2nd card
    let displayCards = cards;
    let showEye = false;

    if (position === 'bottom' && isSqueezeEnabled && cards.length >= 2 && !winner) {
        showEye = true;
        // Show first card, hide second (or show back)
        // We render only the first one fully, and a "back" for the second
        // But for visual consistency we might want to just render the back
        // However, PlayingCard handles 'hidden' prop.
        // Let's create a modified display list.
        // We can't modify the objects directly if they are frozen, so map new ones.
        // Actually, we can just pass a special flag or just handle it in render
    }

    return (
        <div className={`absolute ${styleClass} flex flex-col items-center transition-all duration-300 z-10 ${isFolded ? 'opacity-60 scale-90' : ''} ${isWinner ? 'scale-110 z-20' : ''}`}>
            
            {/* Last Action Bubble */}
            {player.lastAction && (
                <div className="mb-2 bg-white/90 text-black text-xs font-bold px-2 py-1 rounded shadow-lg animate-in fade-in slide-in-from-bottom-2 whitespace-nowrap">
                    {player.lastAction}
                </div>
            )}

            {/* Avatar & Info */}
            <div className={`relative w-20 h-20 rounded-full border-4 flex flex-col items-center justify-center bg-gray-800 shadow-xl
                ${isTurn ? 'border-yellow-400 shadow-[0_0_15px_rgba(250,204,21,0.6)]' : 'border-gray-600'}
                ${isWinner ? 'border-amber-500 shadow-[0_0_30px_rgba(245,158,11,0.8)]' : ''}
            `}>
                <div className="text-white/80">
                    {isWinner ? <Trophy className="w-8 h-8 text-yellow-400" /> : <User className="w-8 h-8" />}
                </div>
                
                {/* Winner Crown */}
                {isWinner && (
                    <div className="absolute -top-6 text-2xl animate-bounce">👑</div>
                )}
            </div>

            {/* Name & Chips */}
            <div className="mt-2 bg-black/60 backdrop-blur-sm px-3 py-1 rounded-full text-center border border-white/10 min-w-[80px]">
                <div className="text-xs text-gray-300 font-bold truncate max-w-[100px]">{player.name}</div>
                <div className="text-xs text-yellow-400 font-mono">¥{player.chips}</div>
            </div>

            {/* Cards Area */}
            <div className="absolute top-4 left-16 flex -space-x-8 pl-4">
                {cards.length > 0 ? (
                    displayCards.map((card, idx) => {
                        // Check if this card should be hidden due to squeeze mode
                        // If it's the second card (index 1) and we are showing eye
                        const isHiddenSqueeze = showEye && idx === 1;
                        
                        return (
                            <div 
                                key={idx} 
                                className="transform hover:-translate-y-4 transition-transform duration-200 origin-bottom-left"
                                style={{ transform: `rotate(${(idx - (cards.length-1)/2) * 10}deg)` }}
                            >
                                <PlayingCard 
                                    name={card.name} 
                                    suit={card.suit} 
                                    size="sm" 
                                    hidden={isHiddenSqueeze} 
                                />
                            </div>
                        );
                    })
                ) : (
                    // Show back if cards are hidden (e.g. other players) but hand is not empty/unknown
                    // The backend sends "[Hidden]" for others.
                    // If handStr is "[Hidden]", we show 2 backs usually (or however many cards they have - logic might need to know count)
                    // Currently backend doesn't send count, just "[Hidden]".
                    // We assume 2 cards for simplicity or just show backs if hand is present but empty array
                    handStr === "[Hidden]" && (
                        <>
                            <div className="transform -rotate-6"><PlayingCard name="" suit="" hidden size="sm" /></div>
                            <div className="transform rotate-6 -ml-8"><PlayingCard name="" suit="" hidden size="sm" /></div>
                        </>
                    )
                )}
            </div>

            {/* Squeeze Button */}
            {showEye && (
                <button 
                    onClick={onOpenSqueeze}
                    className="absolute top-10 right-[-40px] p-2 bg-yellow-500/80 hover:bg-yellow-500 text-black rounded-full shadow-lg transition-all animate-pulse"
                    title="搓牌"
                >
                    <Eye className="w-4 h-4" />
                </button>
            )}
        </div>
    );
};

export default PlayerSeat;
