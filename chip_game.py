import random
from play_rule import deal_hands, rank_hands, point_value, HandRank

class Player:
    def __init__(self, name, chips, is_bot=False, bot=None, action_provider=None):
        self.name = name  # 玩家名称
        self.chips = chips  # 当前筹码
        self.is_bot = is_bot  # 是否为 BOT
        self.bot = bot  # BOT 实例
        self.action_provider = action_provider # 动作提供者回调
        self.hand = None  # 当前手牌
        self.folded = False  # 是否已弃牌
        self.has_bet = False  # 本局是否下注过
        self.last_bet = 0  # 本局最后一次下注金额
        self.last_bet_order = 0  # 本局下注顺序编号

class ChipGame:
    def __init__(self, player_configs, starting_chips=10, rng=None, observer=None):
        self.players = []  # 玩家列表
        self.observer = observer # 观察者回调 (event_type, data)
        for item in player_configs:
            if isinstance(item, Player):
                self.players.append(item)
                continue
            if isinstance(item, dict):
                name = item["name"]
                chips = item.get("chips", starting_chips)
                is_bot = item.get("is_bot", False)
                bot = item.get("bot")
                self.players.append(Player(name, chips, is_bot=is_bot, bot=bot))
                continue
            self.players.append(Player(item, starting_chips))
        self.pot = 0  # 当前底池
        self.last_winner_index = None  # 上一局收池玩家索引
        self.last_tie_bettor_index = None  # 上一局平局中最后下注玩家索引
        self.last_folder_index = None  # 上一局最后弃牌玩家索引
        self.round_index = 0  # 局数
        self.rng = rng or random.Random()  # 随机数生成器
        self.round_logs = [] # 当前局日志 (实时更新)

    def _notify_observer(self, event_type, data=None):
        if self.observer:
            self.observer(event_type, data)

    def _start_index(self):
        if self.last_winner_index is not None:
            return self.last_winner_index
        if self.last_tie_bettor_index is not None:
            return self.last_tie_bettor_index
        if self.last_folder_index is not None:
            return self.last_folder_index
        return self.rng.randrange(len(self.players))

    def _cycle_indices(self, start_index):
        count = len(self.players)
        return [(start_index + i) % count for i in range(count)]

    def _prepare_round(self):
        names = [p.name for p in self.players]
        hands = deal_hands(names, self.rng)
        hand_map = {name: hand for name, hand in hands}
        for player in self.players:
            player.folded = player.chips <= 0
            player.has_bet = False
            player.last_bet = 0
            player.last_bet_order = 0
            player.hand = None if player.folded else hand_map[player.name]

    def _collect_ante(self):
        for player in self.players:
            if player.folded:
                continue
            if player.chips <= 0:
                player.folded = True
                player.hand = None
                continue
            player.chips -= 1
            self.pot += 1

    def _get_player_action(self, player, phase):
        if player.chips <= 0:
            return "fold", 0
        
        # If player object has a custom action provider, use it
        if hasattr(player, 'action_provider') and player.action_provider:
            return player.action_provider(player, phase, self.pot, self)
            
        # Default CLI interaction (Fallback)
        if phase == "initial":
            if self.pot <= 0:
                return "fold", 0
            while True:
                choice = input(f"{player.name} 请选择 1下注 2弃牌: ").strip()
                if choice == "2":
                    return "fold", 0
                if choice == "1":
                    while True:
                        amount_input = input(f"{player.name} 下注数量(1~{min(self.pot, player.chips)}): ").strip()
                        if not amount_input.isdigit():
                            continue
                        amount = int(amount_input)
                        if 1 <= amount <= min(self.pot, player.chips):
                            return "bet", amount
        if self.pot <= 0:
            return "check", 0
        if player.chips < self.pot:
            return "check", 0
        while True:
            choice = input(f"{player.name} 请选择 1过牌 2下注: ").strip()
            if choice == "1":
                return "check", 0
            if choice == "2":
                return "bet", self.pot

    def _get_bot_action(self, player, phase, any_bet=False):
        if player.bot is None:
            return ("fold", 0) if phase == "initial" else ("check", 0)
        context = {
            "pot": self.pot,
            "chips": player.chips,
            "phase": phase,
            "hand": player.hand,  # 传入当前手牌
            "player_count": len([p for p in self.players if not p.folded]), # 传入存活玩家数量
            "base_pot": len(self.players), # 基础底池 (总玩家数/初始底池)
            "any_bet": any_bet  # 是否已有下注
        }
        if phase == "initial":
            return player.bot.decide_initial_action(context)
        return player.bot.decide_follow_action(context)

    def _choose_action(self, player, phase, any_bet=False):
        if player.is_bot:
            action, amount = self._get_bot_action(player, phase, any_bet=any_bet)
        else:
            action, amount = self._get_player_action(player, phase)
        
        if phase == "initial":
            # 如果没人下注 (any_bet=False)，本游戏强制要求 下注 或 弃牌 (不允许 Check)
            # 用户规则: "第一次轮到自己，只能下注或者弃牌"
            allowed_actions = ["fold", "bet"]
            # if not any_bet:
            #     allowed_actions.append("check")
                
            if action not in allowed_actions:
                # 如果尝试 check 但不允许 (面对下注或首轮强制)，则视为 fold
                return "fold", 0
                
            if action == "bet":
                amount = min(amount, player.chips, self.pot) # 下注上限为底池 (Pot Limit)
                if amount <= 0:
                    # 如果下注 0，视为 check (如果允许) 或 fold
                    return "check", 0 if not any_bet else "fold", 0
            return action, amount
            
        if action not in ["check", "bet"]:
            return "check", 0
        if action == "bet":
            if player.chips < self.pot:
                return "check", 0
            return "bet", self.pot
        return "check", 0

    def _betting_round(self, start_index, logs=None):
        # 执行一轮下注，直到无人再下注
        # logs 参数是为了兼容旧代码，实际上现在推荐直接用 self.round_logs
        target_logs = self.round_logs
        
        bet_order = 0
        any_bet = False
        last_bettor_index = None # 记录最后一个下注的玩家索引
        
        count = len(self.players)
        current_idx = start_index
        steps_without_bet = 0 # 连续没有下注的步数
        
        # 循环直到满足终止条件
        while True:
            # 更新公开状态供 CLI 读取
            self.any_bet = any_bet 
            
            # 检查存活玩家数
            active_players = [p for p in self.players if not p.folded]
            if len(active_players) <= 1:
                break
                
            # 终止条件 1: 轮回到最后一个下注者，且期间无人反打 -> 结束
            if last_bettor_index is not None and current_idx == last_bettor_index:
                break
                
            # 终止条件 2: 如果没人下注过 (any_bet=False)，且已经遍历了一整圈 -> 结束
            # 注意: 如果有人 Fold，steps_without_bet 也会增加，确保能结束
            if steps_without_bet >= count:
                break
                
            player = self.players[current_idx]
            
            if player.folded:
                # 跳过已弃牌玩家，视为 Pass
                current_idx = (current_idx + 1) % count
                steps_without_bet += 1
                continue
                
            phase = "initial" if not player.has_bet else "follow"
            action, amount = self._choose_action(player, phase, any_bet=any_bet)
            
            if action == "fold":
                player.folded = True
                self.last_folder_index = current_idx
                target_logs.append(f"[{player.name}] 弃牌 (Fold)")
                steps_without_bet += 1
                
            elif action == "bet":
                pot_before = self.pot
                was_initial = not player.has_bet
                amount = min(amount, player.chips)
                if amount <= 0:
                    target_logs.append(f"[{player.name}] 下注失败 (Amount 0)")
                    steps_without_bet += 1
                else:
                    player.chips -= amount
                    self.pot += amount
                    player.has_bet = True
                    player.last_bet = amount
                    bet_order += 1
                    player.last_bet_order = bet_order
                    
                    label = ""
                    if was_initial and amount == pot_before and not any_bet:
                        label = " (开池)"
                    elif was_initial and amount == pot_before and any_bet:
                        label = " (反打/接招)"
                    elif (not was_initial) and amount == pot_before:
                        label = " (加注/反打)"
                    target_logs.append(f"[{player.name}] 下注 {amount}{label} | 底池: {self.pot} | 剩余: {player.chips}")
                    
                    # 关键: 有人下注，更新状态
                    any_bet = True
                    last_bettor_index = current_idx
                    steps_without_bet = 0 # 重置计数器
            
            else: # check
                if any_bet:
                    # 只有在有人下注后，Check (过牌) 才是有意义的 (Showdown)
                    target_logs.append(f"[{player.name}] 过牌 (Check)")
                # 如果是 initial 阶段 Check (目前已被禁止，但作为防御性代码)，不打印或打印 Check
                
                steps_without_bet += 1
            
            # Notify observer after action
            self._notify_observer("action", {
                "player": player.name,
                "action": action,
                "amount": amount,
                "chips": player.chips,
                "pot": self.pot,
                "log": target_logs[-1] if target_logs else ""
            })
                
            current_idx = (current_idx + 1) % count


    def _hand_rank_name(self, hand):
        if hand.rank == HandRank.PAIR:
            return f"对子 (子等级:{hand.sub_rank})"
        if hand.rank <= HandRank.POINT_9:
            return f"{hand.rank.value}点 (最大权重:{hand.max_weight})"
        return hand.rank.name

    def play_round(self, log_actions=True):
        # 开局流程：补池判断 -> 收底注 -> 发牌 -> 下注 -> 结算
        self.round_index += 1
        self.round_logs = []
        
        # 1. 重置玩家状态 (修正 Ante 漏人 Bug)
        for player in self.players:
            if player.chips > 0:
                player.folded = False
            # has_bet 等状态在 _prepare_round 会再次重置，但 folded 需要先重置以便收 Ante

        threshold = (len(self.players) + 1) // 2
        if self.pot < threshold:
            # 仅在开局判断是否补池
            self._collect_ante()
        self._prepare_round()

        if log_actions:
            self.round_logs.append(f"开局底池 {self.pot}")
            for player in self.players:
                if player.folded:
                    self.round_logs.append(f"{player.name} 无筹码，自动弃牌")
                else:
                    self.round_logs.append(f"{player.name} 手牌 {player.hand.cards[0]} {player.hand.cards[1]} -> {self._hand_rank_name(player.hand)}")

        self._notify_observer("round_start", {
            "round": self.round_index,
            "pot": self.pot,
            "players": [{"name": p.name, "chips": p.chips, "folded": p.folded, "hand": str(p.hand) if p.hand else None} for p in self.players]
        })

        start_index = self._start_index()
        self._betting_round(start_index) # 使用内部 self.round_logs

        active_players = [(i, p) for i, p in enumerate(self.players) if not p.folded]
        result = {
            "winner": None,
            "payout": 0,
            "pot": self.pot,
            "logs": self.round_logs,
            "active_players": [p.name for _, p in active_players]
        }
        
        # ... logic for winner ...
        if len(active_players) == 0:
            return result

        if len(active_players) == 1:
            winner_index, winner = active_players[0]
            # 修正规则：如果赢家下注过（主动打跑别人），或者牌力 >= 8 点（捡天水），则获胜
            if winner.has_bet or point_value(winner.hand) >= 8:
                payout = self.pot
                self.pot = 0
                winner.chips += payout
                self.last_winner_index = winner_index
                self.last_tie_bettor_index = None
                result["winner"] = winner.name
                result["payout"] = payout
                reason = "打跑对手" if winner.has_bet else "捡天水"
                self.round_logs.append(f"{winner.name} {reason}，收池 {payout}")
            else:
                winner.folded = True
                self.last_winner_index = None
                self.last_folder_index = winner_index
                self.last_tie_bettor_index = None
                self.round_logs.append(f"{winner.name} 牌力不足 8 点且未下注，弃牌，本局无胜者")
        else:
            ranked = rank_hands([(p.name, p.hand) for _, p in active_players])
            best_hand = ranked[0][1]
            winners = [item for item in active_players if item[1].hand == best_hand]
            if len(winners) > 1:
                self.last_winner_index = None
                winner_bettor = sorted(winners, key=lambda x: x[1].last_bet_order, reverse=True)[0]
                self.last_tie_bettor_index = winner_bettor[0] if winner_bettor[1].last_bet_order > 0 else None
                self.round_logs.append("平局，无人收池")
            else:
                winner_index, winner_player = winners[0]
                payout = min(self.pot, winner_player.last_bet * 2)
                self.pot -= payout
                winner_player.chips += payout
                self.last_winner_index = winner_index
                self.last_tie_bettor_index = None
                result["winner"] = winner_player.name
                result["payout"] = payout
                self.round_logs.append(f"{winner_player.name} 获胜，收池 {payout}")

        result["pot"] = self.pot
        # Add player data for showdown
        result["players"] = [
            {
                "name": p.name,
                "chips": p.chips,
                "folded": p.folded,
                "hand": str(p.hand) if p.hand else None,
                "hand_pts": point_value(p.hand) if p.hand else 0
            } 
            for p in self.players
        ]
        self._notify_observer("round_end", result)
        return result
