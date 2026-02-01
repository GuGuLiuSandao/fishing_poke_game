import { create } from 'zustand';

interface Player {
    name: string;
    chips: number;
    folded: boolean;
    hand: string;
    lastAction?: string;
    isTurn?: boolean;
}

interface GameState {
    players: Player[];
    pot: number;
    roundCount: number;
    winner: string | null;
    history: string[];
    isSqueezeEnabled: boolean;
    isWaitingForReady: boolean;
    // Actions
    setPlayers: (players: Player[]) => void;
    setPot: (pot: number) => void;
    setRoundCount: (count: number) => void;
    setWinner: (winner: string | null) => void;
    addHistory: (entry: string) => void;
    toggleSqueeze: () => void;
    setWaitingForReady: (waiting: boolean) => void;
    resetGame: () => void;
    updatePlayer: (name: string, data: Partial<Player>) => void;
}

export const useGameStore = create<GameState>((set) => ({
    players: [],
    pot: 0,
    roundCount: 0,
    winner: null,
    history: [],
    isSqueezeEnabled: false,
    isWaitingForReady: false,

    setPlayers: (players) => set({ players }),
    setPot: (pot) => set({ pot }),
    setRoundCount: (count) => set({ roundCount: count }),
    setWinner: (winner) => set({ winner }),
    addHistory: (entry) => set((state) => ({ history: [entry, ...state.history] })),
    toggleSqueeze: () => set((state) => ({ isSqueezeEnabled: !state.isSqueezeEnabled })),
    setWaitingForReady: (waiting) => set({ isWaitingForReady: waiting }),
    
    resetGame: () => set({
        players: [],
        pot: 0,
        roundCount: 0,
        winner: null,
        history: [],
        isWaitingForReady: false
    }),

    updatePlayer: (name, data) => set((state) => ({
        players: state.players.map(p => p.name === name ? { ...p, ...data } : p)
    })),
}));
