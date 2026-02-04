import os
import sys
from chip_game import ChipGame, Player
from bot_ai import GeneBot
from fishing_solver import MathBot
from bot_cfr import CFRBot

# CLI 动作提供者：负责与人类玩家通过终端交互
def cli_action_provider(player, phase, pot, game):
    """
    phase: "initial" or "follow"
    pot: current pot amount
    game: ChipGame instance (for context)
    """
    print(f"\n>>> 轮到 {player.name} 行动")
    print(f"    手牌: {player.hand} ({game._get_hand_display_strength(player.hand)})")
    print(f"    当前底池: {pot}")
    print(f"    你的筹码: {player.chips}")

    # 显示本局动态 (Context)
    # 为了避免刷屏，我们可以只显示最近的 N 条，或者全部显示
    # 对于命令行游戏，显示全部当前局日志是有帮助的
    print("\n    --- 本局动态 (Live Logs) ---")
    if hasattr(game, "round_logs"):
        for log in game.round_logs:
            # 隐藏其他玩家的手牌信息
            # 日志格式通常为: "{player.name} 手牌 ..."
            if " 手牌 " in log:
                # 检查是否是当前玩家的手牌
                # 简单判断：如果日志以 "player.name " 开头
                if log.startswith(f"{player.name} "):
                    print(f"    {log}")
                else:
                    # 提取玩家名并隐藏手牌
                    try:
                        name_part = log.split(" 手牌 ")[0]
                        print(f"    {name_part} 手牌 [未知]")
                    except:
                        print(f"    {log}") # Fallback
            else:
                print(f"    {log}")
    else:
        print("    (暂无日志)")
    print("    ----------------------------\n")

    # 获取游戏当前状态 (any_bet)
    any_bet = getattr(game, "any_bet", False)

    if phase == "initial":
        # 初始阶段
        
        if not any_bet:
            # Case 1: 无人下注。可以 Check, Bet, Fold.
            print("当前无人下注。")
            while True:
                print("请选择行动:")
                print("  [1] 过牌 (Check) - 暂不下注")
                print("  [2] 下注 (Bet) - 主动开战")
                print("  [3] 弃牌 (Fold)")
                choice = input("请输入选项 (1/2/3): ").strip()
                
                if choice == "1":
                    return "check", 0
                if choice == "3":
                    return "fold", 0
                if choice == "2":
                    max_bet = min(pot, player.chips)
                    if max_bet <= 0:
                        print("筹码不足或底池为空，只能过牌。")
                        return "check", 0
                    
                    while True:
                        amount_str = input(f"请输入下注金额 (1 ~ {max_bet}): ").strip()
                        if amount_str.isdigit():
                            amount = int(amount_str)
                            if 1 <= amount <= max_bet:
                                return "bet", amount
                            else:
                                print(f"金额必须在 1 到 {max_bet} 之间。")
                        else:
                            print("请输入有效数字。")
                print("无效输入，请重试。")
                
        else:
            # Case 2: 有人下注。必须 Bet (Counter) or Fold.
            print("有人已下注！本游戏无跟注(Call)。")
            print("你必须反打(Bet)以留在局中，或弃牌。")
            
            while True:
                print("请选择行动:")
                print("  [1] 反打 (Bet/Counter) - 支付筹码并反击")
                print("  [2] 弃牌 (Fold)")
                choice = input("请输入选项 (1/2): ").strip()
                
                if choice == "2":
                    return "fold", 0
                if choice == "1":
                    # 反打通常限制为底池大小 (Pot Limit)
                    # 用户只需要确认是否反打，具体金额由规则限制 (通常是 Pot Size)
                    # chip_game 会限制 max bet.
                    # 我们可以让用户输入，也可以默认 Pot.
                    # 为了简单，默认 Pot (即 Counter 全额)
                    max_bet = min(pot, player.chips)
                    if max_bet <= 0: 
                        return "fold", 0
                    
                    # 也可以让用户选金额? 
                    # 规则通常是 Counter = Pot.
                    # 让用户输入吧，但提示最大值.
                    print(f"建议反打金额: {max_bet}")
                    # return "bet", max_bet
                    
                    while True:
                         amount_str = input(f"请输入反打金额 (1 ~ {max_bet}, 回车默认{max_bet}): ").strip()
                         if not amount_str:
                             return "bet", max_bet
                         if amount_str.isdigit():
                             amount = int(amount_str)
                             if 1 <= amount <= max_bet:
                                 return "bet", amount
                             else:
                                 print(f"金额必须在 1 到 {max_bet} 之间。")
                         else:
                             print("请输入有效数字。")
                
                print("无效输入，请重试。")

    else: # phase == "follow"
        # Case 3: 我之前下注过，现在轮回到我 (说明有人 Counter 了我)
        # 此时 Check = Showdown (如果不再加注)
        # Bet = Re-Raise
        print("轮回到你 (你已下注过)。")
        print("对手已反打/接招。")
        
        while True:
            print("请选择行动:")
            print("  [1] 过牌 (Check) - 接受比牌 (Showdown)") 
            print("  [2] 加注 (Raise) - 继续反打 (Re-Raise)") 
            
            choice = input("请输入选项 (1/2): ").strip()
            
            if choice == "1":
                return "check", 0
            if choice == "2":
                if player.chips < pot:
                    print("筹码不足以加注，只能 Check/Showdown。")
                    return "check", 0
                return "bet", pot # Re-Raise 默认 Pot
            
            print("无效输入，请重试。")

def main():
    print("========================================")
    print("      钓鱼 (Fishing) - 单机挑战版")
    print("========================================")
    
    # 1. 设置玩家
    player_name = input("请输入你的名字: ").strip() or "玩家"
    human = Player(player_name, 200, is_bot=False, action_provider=cli_action_provider)
    
    # 2. 选择对手
    print("\n请选择你的对手组合:")
    print("  [1] 新手村 (vs Lv1 & Lv2)")
    print("  [2] 进阶场 (vs Lv3 & MathBot)")
    print("  [3] 巅峰赛 (vs Lv5 & CFRBot & MathBot)")
    print("  [4] 6人大乱斗 (vs All Bots)")
    
    choice = input("请选择 (1-4): ").strip()
    
    opponents = []
    if choice == "1":
        opponents = [
            Player("Lv1_Rookie", 200, is_bot=True, bot=GeneBot(preset_name="Lv1_Rookie")),
            Player("Lv2_Casual", 200, is_bot=True, bot=GeneBot(preset_name="Lv2_Casual"))
        ]
    elif choice == "2":
        opponents = [
            Player("Lv3_Exp", 200, is_bot=True, bot=GeneBot(preset_name="Lv3_Experienced")),
            Player("MathBot", 200, is_bot=True, bot=MathBot())
        ]
    elif choice == "3":
        opponents = [
            Player("Lv5_Legend", 200, is_bot=True, bot=GeneBot(preset_name="Lv5_Legend")),
            Player("CFR_Bot", 200, is_bot=True, bot=CFRBot()),
            Player("MathBot", 200, is_bot=True, bot=MathBot())
        ]
    elif choice == "4":
        opponents = [
            Player("Lv1", 200, is_bot=True, bot=GeneBot(preset_name="Lv1_Rookie")),
            Player("Lv3", 200, is_bot=True, bot=GeneBot(preset_name="Lv3_Experienced")),
            Player("Lv5", 200, is_bot=True, bot=GeneBot(preset_name="Lv5_Legend")),
            Player("MathBot", 200, is_bot=True, bot=MathBot()),
            Player("CFRBot", 200, is_bot=True, bot=CFRBot())
        ]
    else:
        print("默认选择新手村")
        opponents = [
            Player("Lv1_Rookie", 200, is_bot=True, bot=GeneBot(preset_name="Lv1_Rookie"))
        ]
        
    players = [human] + opponents
    
    # 3. 初始化游戏
    game = ChipGame(players, starting_chips=200)
    
    # 辅助方法：显示手牌强度 (需要 Hack 一下 ChipGame 或者 import 工具函数)
    # 为了方便，我们在 cli_action_provider 里调用 game 的内部方法或者 helper
    # 我们需要给 ChipGame 加一个 helper method
    
    round_count = 0
    while True:
        round_count += 1
        print(f"\n\n>>> 第 {round_count} 局开始 | 当前底池: {game.pot} <<<")
        print(f"座位顺序: {' -> '.join([p.name for p in game.players])} (轮流先手)")
        
        # 检查是否破产
        if human.chips <= 0:
            print("\n你破产了！游戏结束。")
            break
        
        # 检查是否只剩一人
        active_players = [p for p in game.players if p.chips > 0]
        if len(active_players) <= 1:
            print(f"\n游戏结束！最终胜者是: {active_players[0].name}")
            break
            
        result = game.play_round(log_actions=True)
        
        # 显示本局日志
        print("\n--- 本局战况 ---")
        for log in result["logs"]:
            print(log)
            
        print(f"\n本局赢家: {result['winner']}")
        print(f"赢取筹码: {result['payout']}")
        
        # 显示当前筹码
        print("\n--- 当前筹码 ---")
        for p in game.players:
            status = " (破产)" if p.chips <= 0 else ""
            print(f"{p.name}: {p.chips}{status}")
            
        # 暂停
        input("\n按回车键继续下一局...")

if __name__ == "__main__":
    # 为了支持显示手牌强度，我们需要在 ChipGame 里加个小 Helper，或者在这里 import
    # 暂时先用简单的 Patch
    from play_rule import point_value
    from bot_ai import get_hand_rank

    def _get_hand_display_strength(hand):
        if not hand: return "未知"
        # 显示点数和排名 (Rank 1 is best, 63 is worst)
        pts = point_value(hand)
        try:
            # hand.cards is [c1, c2]
            rank = get_hand_rank(*hand.cards)
            return f"{pts}点 (Rank {rank})"
        except Exception:
            return f"{pts}点"
        
    ChipGame._get_hand_display_strength = staticmethod(_get_hand_display_strength)
    
    main()
