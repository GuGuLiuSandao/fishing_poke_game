import React, { useState, useEffect } from 'react';
import PlayingCard from './PlayingCard';
import { Eye } from 'lucide-react';

interface Card {
    name: string;
    suit: string;
}

interface SqueezeModeProps {
    cards: Card[];
    onClose: () => void;
}

const SqueezeMode: React.FC<SqueezeModeProps> = ({ cards, onClose }) => {
    const [offset, setOffset] = useState({ x: 0, y: 0 });
    const [isDragging, setIsDragging] = useState(false);
    const [thumbHidden, setThumbHidden] = useState(false);
    
    const handlePointerDown = (e: React.PointerEvent) => { 
        setIsDragging(true); 
    };

    useEffect(() => {
        const handlePointerMove = (e: PointerEvent) => {
            if (!isDragging) return;
            setOffset(prev => ({ x: prev.x + e.movementX, y: prev.y + e.movementY }));
        };
        const handlePointerUp = () => { setIsDragging(false); };
        if (isDragging) {
            window.addEventListener('pointermove', handlePointerMove);
            window.addEventListener('pointerup', handlePointerUp);
        }
        return () => {
            window.removeEventListener('pointermove', handlePointerMove);
            window.removeEventListener('pointerup', handlePointerUp);
        }
    }, [isDragging]);

    useEffect(() => {
        setOffset({ x: 0, y: 0 });
        setThumbHidden(false);
    }, [cards]);

    if (!cards || cards.length < 2) return null;

    return (
        <div className="fixed inset-0 z-[100] flex flex-col items-center justify-center bg-black/95 backdrop-blur-md animate-in fade-in duration-200">
            <div className="text-yellow-500 font-bold mb-8 text-xl tracking-widest flex items-center gap-2">
                <Eye className="w-6 h-6" /> 沉浸搓牌模式
            </div>
            <div className="relative w-48 h-72">
                {/* 底牌 (第二张) */}
                <div className="absolute inset-0">
                    <PlayingCard name={cards[1].name} suit={cards[1].suit} size="lg" showThumb={!thumbHidden} onThumbClick={() => setThumbHidden(true)} />
                </div>
                {/* 顶牌 (第一张) - 可拖动 */}
                <div 
                    className="absolute inset-0 cursor-move shadow-[0_20px_50px_rgba(0,0,0,0.5)] transition-transform duration-75 ease-out"
                    style={{ transform: `translate(${offset.x}px, ${offset.y}px) rotate(${offset.x * 0.05}deg)` }}
                    onPointerDown={handlePointerDown}
                >
                    <PlayingCard name={cards[0].name} suit={cards[0].suit} size="lg" />
                    <div className="absolute inset-0 flex items-center justify-center pointer-events-none opacity-20">
                        {!isDragging && offset.x === 0 && <span className="text-black font-bold text-lg">按住拖动</span>}
                    </div>
                </div>
            </div>
            <button onClick={onClose} className="mt-8 px-8 py-2 bg-white/10 hover:bg-white/20 border border-white/20 rounded-full text-white transition-all">
                完成看牌
            </button>
        </div>
    );
};

export default SqueezeMode;
