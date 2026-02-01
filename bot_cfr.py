import json
import random
import os
from bot_ai import get_hand_rank
from cfr_trainer import NUM_ACTIONS, PASS, BET

class CFRBot:
    def __init__(self, strategy_file="cfr_strategy.json"):
        self.name = "CFR_Bot"
        self.strategy = {}
        self.load_strategy(strategy_file)
        
    def load_strategy(self, filename):
        if os.path.exists(filename):
            with open(filename, "r") as f:
                self.strategy = json.load(f)
        else:
            print(f"Warning: {filename} not found. CFRBot will play randomly.")

    def get_action_probs(self, rank, history_suffix):
        key = f"{rank}|{history_suffix}"
        if key in self.strategy:
            return self.strategy[key]
        
        # Fallback for unknown states (e.g. re-raises or different history)
        # Try to find a similar state
        # If facing bet (b), and key not found (maybe pb?), try 'b'
        if "b" in history_suffix:
            fallback_key = f"{rank}|b"
            if fallback_key in self.strategy:
                return self.strategy[fallback_key]
                
        # Default: 50/50
        return [0.5, 0.5]

    def _sample_action(self, probs):
        r = random.random()
        if r < probs[PASS]:
            return PASS
        return BET

    def _get_adjusted_rank(self, hand, player_count):
        if hasattr(hand, 'cards'):
            rank = get_hand_rank(hand.cards[0], hand.cards[1])
        else:
            rank = 63
            
        # 启发式调整: 针对多人局适当放宽
        # 在 1v1 中，我们只玩 Top ~15% 的牌。
        # 在 6 人局中，我们需要玩 Top ~30-40% 的牌。
        # 将 Rank 除以 2 可以将 Rank 30 映射为 15。
        if player_count > 2:
            rank = rank // 2
            rank = max(1, rank)
        return rank

    def decide_initial_action(self, context):
        hand = context.get("hand")
        pot = context["pot"]
        chips = context["chips"]
        any_bet = context.get("any_bet", False)
        player_count = context.get("player_count", 2)
        
        # 1. 获取调整后的牌力等级
        rank = self._get_adjusted_rank(hand, player_count)
            
        # 3. 确定历史后缀
        # 如果尚未下注 -> "" (开局)
        # 如果已有下注 -> "b" (防守/跟牌)
        suffix = "b" if any_bet else ""
        
        # 4. 获取策略
        probs = self.get_action_probs(rank, suffix)
        action_code = self._sample_action(probs)
        
        if action_code == PASS:
            return "check", 0
        else:
            # 下注策略: 标准尺寸
            target = max(1, pot // 2 + 1)
            amount = min(target, chips)
            return "bet", amount

    def decide_follow_action(self, context):
        # 此函数在玩家已经下注，但后续又有其他玩家下注（反打）时被调用。
        # 我们的简化版 CFR 策略树（最大深度为 2 次下注）可能未完全覆盖多次反打的情况。
        # 但通常来说，如果我们主动下注后遭遇反打，说明对手牌力强或者是诈唬。
        # 此时底池已经很大，如果我们有一定的胜率，应该倾向于“过牌（Check）”进行开牌比大小。
        
        hand = context.get("hand")
        chips = context["chips"]
        pot = context["pot"]
        player_count = context.get("player_count", 2)
        
        # 1. 获取调整后的牌力等级 (使用与初始行动相同的启发式逻辑)
        rank = self._get_adjusted_rank(hand, player_count)
            
        # Rank 1 最强, 63 最弱。
        # 调整后的 Rank <= 25 意味着原始 Rank <= 50 (前 80%?) 不完全是。
        # 原始 Rank 30 // 2 = 15。
        # CFR 策略通常会防守前 20% (Rank <= 12)。
        # 因此原始 Rank <= 24 将会被防守。
        
        # 我们为“套池 (Pot Committed)”情况设定一个硬性底线。
        if rank <= 25: 
            target = max(1, pot // 2 + 1)
            amount = min(target, chips)
            return "bet", amount
        else:
            return "check", 0 # 弃牌 (Fold)
