import random
import json
import pickle
import os
from collections import defaultdict
from play_rule import deal_hands, Card, Suit, Color
from bot_ai import get_hand_rank

# Actions
PASS = 0
BET = 1
NUM_ACTIONS = 2

class CFRNode:
    def __init__(self):
        self.regret_sum = [0.0] * NUM_ACTIONS
        self.strategy_sum = [0.0] * NUM_ACTIONS

    def get_strategy(self, realization_weight):
        # Regret Matching
        normalizing_sum = 0
        strategy = [0.0] * NUM_ACTIONS
        for a in range(NUM_ACTIONS):
            strategy[a] = max(self.regret_sum[a], 0)
            normalizing_sum += strategy[a]
        
        for a in range(NUM_ACTIONS):
            if normalizing_sum > 0:
                strategy[a] /= normalizing_sum
            else:
                strategy[a] = 1.0 / NUM_ACTIONS
            self.strategy_sum[a] += realization_weight * strategy[a]
        
        return strategy

    def get_average_strategy(self):
        normalizing_sum = sum(self.strategy_sum)
        avg_strategy = [0.0] * NUM_ACTIONS
        for a in range(NUM_ACTIONS):
            if normalizing_sum > 0:
                avg_strategy[a] = self.strategy_sum[a] / normalizing_sum
            else:
                avg_strategy[a] = 1.0 / NUM_ACTIONS
        return avg_strategy

class CFRTrainer:
    def __init__(self):
        # Map: "rank|history" -> Node
        self.node_map = defaultdict(CFRNode) 

    def get_node(self, card_rank, history):
        key = f"{card_rank}|{history}"
        return self.node_map[key]

    def train(self, iterations):
        print(f"Starting CFR Training for {iterations} iterations...")
        util = 0
        for i in range(iterations):
            # 1. Deal Cards
            hands_list = deal_hands(["P1", "P2"])
            # hands_list is [(name, hand), (name, hand)]
            h1 = hands_list[0][1]
            h2 = hands_list[1][1]
            
            # get_hand_rank takes c1, c2
            rank1 = get_hand_rank(h1.cards[0], h1.cards[1])
            rank2 = get_hand_rank(h2.cards[0], h2.cards[1])
            
            # 2. Run CFR
            # Player 0 starts.
            util += self.cfr(rank1, rank2, "", 1.0, 1.0)
            
            if (i+1) % 1000 == 0:
                print(f"Iteration {i+1}/{iterations}, Avg Util: {util/(i+1):.4f}")

    def cfr(self, rank1, rank2, history, p0, p1):
        plays = len(history)
        player = plays % 2
        opponent = 1 - player
        
        # Terminal States
        if plays >= 2:
            # Possible terminal histories:
            # pp (Check-Check)
            # pbp (Check-Bet-Fold) -> P2 Wins
            # pbb (Check-Bet-Showdown) -> Showdown (P2 accepted P1's bet)
            # bp (Bet-Fold) -> P1 Wins
            # bb (Bet-Showdown) -> Showdown (P2 accepted P1's bet)
            
            if history == "pp":
                return self.get_showdown_payoff(rank1, rank2, pot=2)
            elif history == "pbp":
                return -1 # P1 folds, loses Ante 1. P2 wins 1. (View from P1)
            elif history == "pbb":
                return self.get_showdown_payoff(rank1, rank2, pot=6) # Ante 1+1, Bet 2+2. Total 6.
            elif history == "bp":
                return 1 # P2 folds, P1 wins Ante 1.
            elif history == "bb":
                return self.get_showdown_payoff(rank1, rank2, pot=6)
                
        node = self.get_node(rank1 if player == 0 else rank2, history)
        strategy = node.get_strategy(p0 if player == 0 else p1)
        
        util = [0.0] * NUM_ACTIONS
        node_util = 0
        
        for a in range(NUM_ACTIONS):
            next_history = history + ("p" if a == PASS else "b")
            
            if player == 0:
                util[a] = -self.cfr(rank1, rank2, next_history, p0 * strategy[a], p1)
            else:
                util[a] = -self.cfr(rank1, rank2, next_history, p0, p1 * strategy[a])
                
            node_util += strategy[a] * util[a]
            
        # Update Regrets
        for a in range(NUM_ACTIONS):
            regret = util[a] - node_util
            node.regret_sum[a] += (p1 if player == 0 else p0) * regret
            
        return node_util

    def get_showdown_payoff(self, rank1, rank2, pot):
        # rank1, rank2: 1 is Best, 63 is Worst.
        # Payoff is from P1's perspective.
        # Net Profit = Win Amount - Investment.
        # If Pot=2 (Ante 1 each). Winner gets 2. Net +1. Loser -1.
        # If Pot=6 (Ante 1+1, Bet 2+2). Winner gets 6. Net +3. Loser -3.
        
        payoff = pot / 2 
        
        if rank1 < rank2: # P1 wins (Lower rank is better)
            return payoff
        elif rank1 > rank2: # P2 wins
            return -payoff
        else:
            return 0 # Tie

    def save_strategy(self, filename="cfr_strategy.json"):
        # Convert nodes to simple dict
        strategy_map = {}
        for key, node in self.node_map.items():
            avg_strat = node.get_average_strategy()
            # Clean up small probabilities
            avg_strat = [round(x, 4) for x in avg_strat]
            strategy_map[key] = avg_strat
            
        with open(filename, "w") as f:
            json.dump(strategy_map, f)
        print(f"Strategy saved to {filename}")

if __name__ == "__main__":
    trainer = CFRTrainer()
    trainer.train(100000)
    trainer.save_strategy("cfr_strategy.json")
