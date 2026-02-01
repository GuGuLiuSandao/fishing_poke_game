from chip_game import ChipGame
from bot_ai import GeneBot
from fishing_solver import MathBot
from bot_cfr import CFRBot

def simulate(rounds=5, starting_chips=20):
    # 定义 5 个不同等级的 AI (基于新版非德州逻辑)
    bot_configs = [
        {
            "name": "MathSolver (数学家)",
            "desc": "基于严谨 EV 和凯利公式的求解器",
            "bot": MathBot()
        },
        {
            "name": "CFR_Bot (纳什均衡)",
            "desc": "基于后悔值最小化算法训练的 GTO 策略",
            "bot": CFRBot()
        },
        {
            "name": "Lv1_Rookie (新手)",
            "desc": "基本随机乱打或过于胆小",
            "bot": GeneBot(preset_name="Lv1_Rookie")
        },
        {
            "name": "Lv2_Casual (休闲)",
            "desc": "策略较弱",
            "bot": GeneBot(preset_name="Lv2_Casual")
        },
        {
            "name": "Lv3_Experienced (老手)",
            "desc": "中坚力量",
            "bot": GeneBot(preset_name="Lv3_Experienced")
        },
        {
            "name": "Lv4_Master (大师)",
            "desc": "实力强劲",
            "bot": GeneBot(preset_name="Lv4_Master")
        },
        {
            "name": "Lv5_Legend (传奇)",
            "desc": "适应度最高，策略极具针对性",
            "bot": GeneBot(preset_name="Lv5_Legend")
        }
    ]

    print("=== 参赛 BOT 介绍 ===")
    players = []
    for config in bot_configs:
        print(f"[{config['name']}] - {config['desc']}")
        players.append({
            "name": config["name"],
            "chips": starting_chips,
            "is_bot": True,
            "bot": config["bot"]
        })
    
    print("\n=== 游戏开始 ===")
    game = ChipGame(players, starting_chips=starting_chips)
    
    for i in range(rounds):
        print(f"\n=== 第 {i+1} 局 ===")
        result = game.play_round(log_actions=True)
        for log in result["logs"]:
            print(log)
        
        winner_text = result['winner'] if result['winner'] else "无 (平局或全弃)"
        print(f"本局胜者: {winner_text}")
        print(f"本局收池: {result['payout']}")
        print(f"本局结束底池: {result['pot']}")
        
        print("-" * 20)
        print("当前筹码榜:")
        sorted_players = sorted(game.players, key=lambda p: p.chips, reverse=True)
        for player in sorted_players:
            print(f"{player.name}: {player.chips}")

if __name__ == "__main__":
    # Run simulation
    # Reduced rounds to 50 for detailed debugging
    simulate(rounds=50, starting_chips=200)
