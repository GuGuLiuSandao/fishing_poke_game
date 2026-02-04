
import { create } from 'zustand';

export interface Player {
    name: string;
    chips: number;
    folded: boolean;
    hand: string;
    lastAction?: string;
    isTurn?: boolean;
}

export interface Seat {
    type: 'human' | 'bot';
    name: string;
    bot_type?: string;
    status?: 'online' | 'offline';
}

export interface GameState {
    // Lobby State
    nickname: string | null;
    lobbySeats: (Seat | null)[];
    gameStarted: boolean;

    // Game State
    players: Player[];
    pot: number;
    roundCount: number;
    winner: string | null;
    history: string[];
    isSqueezeEnabled: boolean;
    isWaitingForReady: boolean;
    hasBetThisRound: boolean;
    hasPriorBets: boolean;
    currentPhase: 'initial' | 'follow' | null;
    
    // Actions
    setNickname: (name: string) => void;
    setLobbyState: (seats: (Seat | null)[], gameStarted: boolean) => void;
    
    setPlayers: (players: Player[]) => void;
    setPot: (pot: number) => void;
    setRoundCount: (count: number) => void;
    setWinner: (winner: string | null) => void;
    addHistory: (entry: string) => void;
    toggleSqueeze: () => void;
    setWaitingForReady: (waiting: boolean) => void;
    setHasBetThisRound: (hasBet: boolean) => void;
    setHasPriorBets: (hasPrior: boolean) => void;
    setCurrentPhase: (phase: 'initial' | 'follow' | null) => void;
    resetGame: () => void;
    updatePlayer: (name: string, data: Partial<Player>) => void;
}

export const useGameStore = create<GameState>((set) => ({
    nickname: null,
    lobbySeats: Array(6).fill(null),
    gameStarted: false,

    players: [],
    pot: 0,
    roundCount: 0,
    winner: null,
    history: [],
    isSqueezeEnabled: false,
    isWaitingForReady: false,
    hasBetThisRound: false,
    hasPriorBets: false,
    currentPhase: null,

    setNickname: (name) => set({ nickname: name }),
    setLobbyState: (seats, gameStarted) => set({ lobbySeats: seats, gameStarted }),

    setPlayers: (players) => set({ players }),
    setPot: (pot) => set({ pot }),
    setRoundCount: (count) => set({ roundCount: count }),
    setWinner: (winner) => set({ winner }),
    addHistory: (entry) => set((state) => ({ history: [entry, ...state.history] })),
    toggleSqueeze: () => set((state) => ({ isSqueezeEnabled: !state.isSqueezeEnabled })),
    setWaitingForReady: (waiting) => set({ isWaitingForReady: waiting }),
    setHasBetThisRound: (hasBet) => set({ hasBetThisRound: hasBet }),
    setHasPriorBets: (hasPrior) => set({ hasPriorBets: hasPrior }),
    setCurrentPhase: (phase) => set({ currentPhase: phase }),
    
    resetGame: () => set({
        players: [],
        pot: 0,
        roundCount: 0,
        winner: null,
        history: [],
        isWaitingForReady: false,
        hasBetThisRound: false,
        hasPriorBets: false,
        currentPhase: null,
        gameStarted: false // Also reset gameStarted to show lobby? Or controlled by server? 
        // Server sends lobby_update with game_started=False when reset.
    }),

    updatePlayer: (name, data) => set((state) => ({
        players: state.players.map(p => p.name === name ? { ...p, ...data } : p)
    })),
}));
