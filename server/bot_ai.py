import random
from play_rule import Hand
from hand_rankings import POWER_TO_RANK
try:
    from bot_presets import BOT_PRESETS
except ImportError:
    BOT_PRESETS = {}

def get_hand_rank(c1, c2):
    hand = Hand([c1, c2])
    # key format: (rank_value, sub_rank, max_weight)
    key = (hand.rank.value, hand.sub_rank, hand.max_weight)
    return POWER_TO_RANK.get(key, 63)

class GeneBot:
    """
    GeneBot (非德州逻辑版)
    完全摒弃德州扑克术语 (如 Call/Raise/Odds)，基于本游戏独特的“下注即反打”规则设计。
    
    核心逻辑：
    1. 只有“敢不敢打”(Confidence) 和 “想赢多少”(Greed)。
    2. 面对下注，没有“平跟”，只有“硬刚”(Counter) 或 “认怂”(Fold)。
    """
    def __init__(self, genome=None, preset_name=None, rng=None):
        """
        :param genome: 基因参数
        :param preset_name: 预设名称
        """
        self.rng = rng or random.Random()

        if preset_name and preset_name in BOT_PRESETS:
            self.genome = BOT_PRESETS[preset_name]
        else:
            self.genome = genome if genome else self._default_genome()
            
        # 解包新参数体系
        # 1. 信心阈值 (Entry Confidence): 牌力达到多少才敢主动入局？(0.0~1.0)
        self.entry_conf = self.genome.get("entry_conf", 0.6)
        
        # 2. 反击阈值 (Counter Confidence): 别人打我，我牌力达到多少才敢反打？(0.0~1.0)
        # 通常比 entry_conf 更高，因为有人下注说明对方有牌
        self.counter_conf = self.genome.get("counter_conf", 0.7)
        
        # 3. 贪婪因子 (Greed Factor): 决定下注力度。 (0.5~3.0)
        # 牌力越强，下注越大。Greed 放大这个倍数。
        self.greed = self.genome.get("greed", 1.5)
        
        # 4. 诈唬概率 (Bluff Chance): 没牌时硬打的概率。 (0.0~0.5)
        self.bluff = self.genome.get("bluff", 0.1)

    def _default_genome(self):
        return {
            "entry_conf": 0.6,
            "counter_conf": 0.7,
            "greed": 1.5,
            "bluff": 0.1
        }

    def _get_raw_win_rate(self, hand, player_count=2):
        """计算绝对牌力胜率 (不考虑赔率，只看牌)"""
        if hasattr(hand, 'cards'):
            c1, c2 = hand.cards
        else:
            c1, c2 = hand
            
        rank = get_hand_rank(c1, c2)
        # 基础胜率 (战胜随机单人)
        p_single = (64 - rank) / 63.0
        
        # 多人局修正 (简单指数衰减)
        # 在这个游戏里，只要比最大的那个人大就行，所以近似于 P^N
        exponent = max(1, player_count - 1)
        win_rate = p_single ** exponent
        return win_rate

    def decide_initial_action(self, context):
        """
        先手决策：只有 Bet 或 Check (如果不允许Check则Fold)
        """
        hand = context.get("hand")
        if not hand: return "fold", 0
        
        player_count = context.get("player_count", 2)
        win_rate = self._get_raw_win_rate(hand, player_count)
        
        should_bet = False
        
        # 1. 实力判断
        if win_rate > self.entry_conf:
            should_bet = True
            
        # 2. 诈唬判断 (偷鸡)
        # 只有在牌力很弱的时候才叫诈唬，牌力强叫价值
        elif win_rate < 0.3 and self.rng.random() < self.bluff:
            should_bet = True
            
        if should_bet:
            amount = self._calculate_bet(win_rate, context)
            return "bet", amount
            
        # 默认弃牌 (如果规则不允许 Check，且没牌力/没偷鸡，只能 Fold)
        return "fold", 0

    def decide_follow_action(self, context):
        """
        后手决策：面对对手下注
        选项：Fold 或 Bet (反打)
        注意：本游戏无“跟注”(Call)，必须“反打”(Bet) 才能开牌或反击。
        """
        hand = context.get("hand")
        if not hand: return "fold", 0
        
        player_count = context.get("player_count", 2)
        win_rate = self._get_raw_win_rate(hand, player_count)
        
        should_fight = False
        
        # 1. 反击判断
        # 面对下注，我们需要更高的自信
        if win_rate > self.counter_conf:
            should_fight = True
            
        # 2. 诈唬反打 (Bluff Counter)
        # 这种操作极具风险，通常需要极高的 Bluff 值
        elif win_rate < 0.3 and self.rng.random() < self.bluff * 0.5: # 诈唬反打概率减半
            should_fight = True
            
        if should_fight:
            # 反打金额：
            # 如果是反打，通常至少要匹配底池 (或者对手的下注)，或者更重
            amount = self._calculate_bet(win_rate, context, is_counter=True)
            return "bet", amount
            
        return "check", 0

    def _calculate_bet(self, win_rate, context, is_counter=False):
        """
        计算下注额 (离散化版)
        基于：牌力 * 贪婪因子 映射到两个档位
        # 选项：
        # 1. 最小注 (1)
        # 2. 满池注 (Pot)
        # (取消中间档位 Base Pot，以符合“只能下1或Pot”的规则)
        """
        pot = context["pot"]
        chips = context["chips"]
        
        # 基础力度：胜率越高，力度越大
        strength = max(0.0, min(1.0, win_rate))
        
        # 综合得分 = 牌力 * 贪婪因子
        # score 越高，越倾向于重注
        score = strength * self.greed
        
        # 如果是反打，稍微降低一点门槛 (或者增加分数)，表现出更有攻击性
        if is_counter:
            score *= 1.1

        # 档位判断逻辑
        # 调整阈值：score > 1.0 时下满池，否则下 1
        
        bet_choice = 1
        
        if score > 1.0:
            # 高分 -> 满池 (All-in Pot)
            bet_choice = pot
        else:
            # 低分 -> 最小试探
            bet_choice = 1
            
        # 最终校验
        # 1. 不能超过现有筹码
        # 2. 不能超过底池上限 (Pot Limit)
        # 3. 至少为 1
        
        max_allowed = min(pot, chips)
        
        # 如果选择的档位超过了上限，就降档使用最大可用值
        final_amount = min(bet_choice, max_allowed)
        
        # 确保至少下 1 (除非 max_allowed < 1，那也没办法，交由 Game 处理)
        final_amount = max(1, final_amount)
        
        return final_amount
