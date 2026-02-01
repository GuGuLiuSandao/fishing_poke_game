import React, { useState, useEffect } from 'react';

interface PlayingCardProps {
    name: string;
    suit: string;
    hidden?: boolean;
    folded?: boolean;
    size?: 'sm' | 'md' | 'lg';
    showThumb?: boolean;
    onThumbClick?: () => void;
    onClick?: () => void;
}

const PlayingCard: React.FC<PlayingCardProps> = ({ 
    name, 
    suit, 
    hidden = false, 
    folded = false, 
    size = "md", 
    showThumb = false, 
    onThumbClick, 
    onClick 
}) => {
    const [imgError, setImgError] = useState(false);

    // Reset error state when card changes
    useEffect(() => {
        setImgError(false);
    }, [name, suit, hidden]);

    const getCardImage = () => {
        if (hidden) return "https://deckofcardsapi.com/static/img/back.png";

        // Map suits
        let sCode = '';
        if (suit === '♥' || suit === 'Hearts') sCode = 'H';
        else if (suit === '♦' || suit === 'Diamonds') sCode = 'D';
        else if (suit === '♠' || suit === 'Spades') sCode = 'S';
        else if (suit === '♣' || suit === 'Clubs') sCode = 'C';
        
        // Map ranks
        let nCode = '';
        if (name === '10') nCode = '0';
        else if (name === 'A') nCode = 'A';
        else if (name === 'J') nCode = 'J';
        else if (name === 'Q') nCode = 'Q';
        else if (name === 'K') nCode = 'K';
        else nCode = name;

        // Handle Jokers
        if (name === '大王') return "https://deckofcardsapi.com/static/img/X2.png"; // Red Joker
        if (name === '小王') return "https://deckofcardsapi.com/static/img/X1.png"; // Black Joker

        return `https://deckofcardsapi.com/static/img/${nCode}${sCode}.png`;
    };

    const isRed = suit === '♥' || suit === '♦' || suit === '红';
    let suitIcon = suit;
    if(suit === 'Hearts') suitIcon = '♥';
    if(suit === 'Diamonds') suitIcon = '♦';
    if(suit === 'Spades') suitIcon = '♠';
    if(suit === 'Clubs') suitIcon = '♣';

    // CSS Fallback Rendering
    const renderCSSCard = () => {
        if (hidden) {
            return (
                 <div className={`w-full h-full card-back rounded-md border-2 border-white bg-blue-800`}></div>
            );
        }

        const renderBigPatterns = () => {
            if (size !== 'lg') return <div className="text-base sm:text-xl self-center">{suitIcon}</div>;
            
            return <div className="text-6xl self-center">{name}</div>; 
        };

        return (
            <div className={`w-full h-full bg-white rounded-md flex flex-col justify-between p-1 ${isRed ? 'text-red-600' : 'text-black'}`}>
                <div className="flex flex-col items-center leading-none w-6">
                    <div>{name}</div>
                    <div className="text-xs mt-0.5">{suitIcon}</div>
                </div>
                {renderBigPatterns()}
                <div className="flex flex-col items-center leading-none self-end transform rotate-180 w-6">
                    <div>{name}</div>
                    <div className="text-xs mt-0.5">{suitIcon}</div>
                </div>
            </div>
        );
    };

    const cardClasses = size === 'lg' 
        ? 'w-48 h-72 rounded-xl shadow-2xl' 
        : 'w-10 h-14 sm:w-12 sm:h-16 card-sm';

    return (
        <div 
            className={`card-container ${cardClasses} relative transition-transform duration-200 ${folded ? 'opacity-50 grayscale' : ''} bg-white rounded-lg`}
            onClick={onClick}
        >
            {!imgError ? (
                <img 
                    src={getCardImage()} 
                    alt={`${name}${suit}`}
                    className="w-full h-full object-contain rounded-lg shadow-md bg-white"
                    onError={() => setImgError(true)}
                />
            ) : (
                renderCSSCard()
            )}

            {size === 'lg' && showThumb && (
                <div 
                    onClick={(e) => { e.stopPropagation(); onThumbClick && onThumbClick(); }}
                    className="absolute top-0 left-0 w-20 h-24 thumb-mask rounded-br-full cursor-pointer z-50 flex items-center justify-center bg-gradient-to-br from-amber-200 to-amber-700 shadow-lg border-r-2 border-b-2 border-amber-900/20"
                    title="点击移开手指"
                >
                    <span className="text-xs text-white/50 font-bold -rotate-45 select-none">点击移开</span>
                </div>
            )}
        </div>
    );
};

export default PlayingCard;
