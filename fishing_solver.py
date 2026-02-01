import random
from bot_ai import get_hand_rank

from play_rule import HandRank, point_value

class MathBot:
    """
    基于严谨数学公式 (EV) 的求解器 BOT
    针对当前特殊规则优化：
    1. 只有下注才能赢钱 (除非是天水/8点以上)
    2. 收益比被限制为 1:1 (赢家收池上限为下注额的2倍)
    这意味着通常需要 >50% 的胜率才能下注 (无底池赔率 (Pot Odds) 概念)
    """
    def __init__(self):
        self.name = "MathSolver"

    def _get_win_probability(self, hand, player_count):
        """
        计算在未知对手手牌情况下的理论胜率
        """
        if hasattr(hand, 'cards'):
            c1, c2 = hand.cards
        else:
            c1, c2 = hand
            
        # 1. 获取绝对牌力 Rank (1 ~ 63)
        rank = get_hand_rank(c1, c2)
        
        # 2. 计算战胜随机单人手牌的概率 P_single
        p_single = (64 - rank) / 63.0
        
        # 3. 计算战胜 N-1 个对手的概率 P_win
        exponent = max(1, player_count - 1)
        p_win = p_single ** exponent
        return p_win

    def decide_initial_action(self, context):
        """
        首位决策 (First Action)
        """
        hand = context.get("hand")
        pot = context["pot"]
        chips = context["chips"]
        player_count = context.get("player_count", 2)
        
        p_win = self._get_win_probability(hand, player_count)
        
        # 判断是否为 "天水" (Natural Winner)
        # 8点及以上，Check 也能赢底池
        is_natural = False
        if hasattr(hand, 'rank'):
             # 注意：HandRank 枚举值 Point_8=8, Point_9=9, Special >=10
             # 所以 rank.value >= 8 即可 (PlayRule 逻辑)
             # 或者直接用 point_value 函数
             if point_value(hand) >= 8:
                 is_natural = True
        
        if is_natural:
            # 天水策略：
            # 如果没人下注，优先 Check (Trap)，引诱对手下注
            # 如果有人下注 (any_bet=True)，必须接招 (Bet/Call)
            if context.get("any_bet", False):
                target = max(1, pot // 2 + 1)
                amount = min(target, chips)
                return "bet", amount
            else:
                return "check", 0
            
        # 非天水策略：必须下注才能赢 (Check 收益为 0)
        # 赔率机制：Bet 1 赢 1 (净利)。收益比 1:1。
        # 需要 P_win > 0.5 才能 +EV
        
        if p_win > 0.5:
            # 胜率极高，下注收池
            # 为了清空底池，应该下注 Pot/2 (因为 Payout = 2*Bet)
            target = max(1, pot // 2 + 1)
            amount = min(target, chips)
            return "bet", amount
            
        else:
            # 胜率不足 50%，下注是负收益
            # 只能 Check (期待后续有人诈唬送钱? 不，check 只能输或平)
            # 最好 Check (保留 Ante)
            return "check", 0

    def decide_follow_action(self, context):
        """
        后位决策 (Follow Action)
        """
        hand = context.get("hand")
        pot = context["pot"] 
        chips = context["chips"]
        player_count = context.get("player_count", 2)
        
        p_win = self._get_win_probability(hand, player_count)
        
        is_natural = False
        if hasattr(hand, 'rank'):
             if point_value(hand) >= 8:
                 is_natural = True
                 
        if is_natural:
            # 天水：必须接招
            # 既然对手已经下注，底池变大了
            # 我们应该反打，并且力度要足以覆盖底池
            target = max(1, pot // 2 + 1)
            amount = min(target, chips)
            return "bet", amount
            
        # 非天水：
        # 只有在胜率 > 50% 时才接招
        if p_win > 0.5:
            target = max(1, pot // 2 + 1)
            amount = min(target, chips)
            return "bet", amount
        else:
            # 胜率低，直接跑
            return "check", 0 # System will convert to Fold

