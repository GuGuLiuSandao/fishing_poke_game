import random
import json
import numpy as np
from chip_game import ChipGame
from bot_ai import GeneBot

# === 新版基因范围定义 ===
GENE_RANGES = {
    "entry_conf": (0.0, 1.0),    # 入局门槛
    "counter_conf": (0.0, 1.0),  # 反击门槛
    "greed": (0.5, 3.0),         # 贪婪因子 (下注倍率)
    "bluff": (0.0, 0.5)          # 诈唬概率
}

def create_random_genome():
    return {k: random.uniform(v[0], v[1]) for k, v in GENE_RANGES.items()}

def crossover(p1, p2):
    child = {}
    for k in GENE_RANGES:
        if random.random() < 0.5:
            child[k] = p1[k]
        else:
            child[k] = p2[k]
    return child

def mutate(genome, mutation_rate=0.1, mutation_scale=0.1):
    new_genome = genome.copy()
    for k in GENE_RANGES:
        if random.random() < mutation_rate:
            change = random.gauss(0, mutation_scale)
            # 特殊处理：greed 变异幅度大一点
            if k == "greed":
                change *= 2.0
            
            val = new_genome[k] + change
            min_v, max_v = GENE_RANGES[k]
            new_genome[k] = max(min_v, min(max_v, val))
    return new_genome

def evaluate_fitness(population, rounds_per_match=50):
    """
    进化大乱斗模式：
    不再使用固定的 Anchor Bot，而是让种群内部随机分组厮杀。
    """
    pop_size = len(population)
    scores = np.zeros(pop_size)
    
    # 每个人至少打 5 场比赛，每场配置不同
    # 模拟真实环境：既有单挑，也有满员桌
    match_configs = [
        2,  # 单挑
        3,  # 三国杀
        6,  # 满员桌
        8   # 超满员
    ]
    
    # 为了减少方差，我们进行多轮随机匹配
    # 每轮让所有人随机分组
    num_tournaments = 5 
    
    for _ in range(num_tournaments):
        # 打乱顺序
        indices = list(range(pop_size))
        random.shuffle(indices)
        
        # 依次分配到不同大小的桌子上
        ptr = 0
        while ptr < pop_size:
            # 随机选择桌子大小
            table_size = random.choice(match_configs)
            
            # 如果剩余人数不够，就用剩下的所有人
            if ptr + table_size > pop_size:
                table_size = pop_size - ptr
            
            if table_size < 2: # 至少2人
                # 如果只剩1人，加入上一桌（如果上一桌没满到爆）
                break
                
            # 组局
            table_indices = indices[ptr : ptr + table_size]
            
            # 构造 ChipGame 需要的 player_configs 格式
            player_configs = []
            for i, idx in enumerate(table_indices):
                bot_instance = GeneBot(genome=population[idx])
                player_configs.append({
                    "name": f"Bot_{idx}",
                    "chips": 100,
                    "is_bot": True,
                    "bot": bot_instance
                })
            
            # === 注入干扰项 (Noise Bot) ===
            # 在 50% 的对局中，强行加入一个 "疯狗" (Maniac) 或者 "随机" (Random)
            # 这迫使进化出的 AI 不能只学会苟活，必须学会抓鸡
            if random.random() < 0.5:
                # Maniac: 极低门槛，极高诈唬
                maniac_genome = {
                    "entry_conf": 0.05,
                    "counter_conf": 0.1,
                    "greed": 2.5,
                    "bluff": 0.8
                }
                player_configs.append({
                    "name": "Maniac_NPC (疯狗)",
                    "chips": 100,
                    "is_bot": True,
                    "bot": GeneBot(genome=maniac_genome)
                })

            # 比赛开始
            game = ChipGame(player_configs, starting_chips=100)
            
            # 运行多局
            for _ in range(rounds_per_match):
                game.play_round()
                
            # 结算：每个人的得分 = 最终筹码 - 初始筹码 + 生存奖励 - 破产惩罚
            for i, idx in enumerate(table_indices):
                # 注意：player_configs 可能被追加了 NPC，但我们只关心 population 中的个体
                # player_configs 的前 len(table_indices) 个就是我们的个体
                final_chips = game.players[i].chips
                net_profit = final_chips - 100
                
                score = net_profit
                
                # 生存激励机制：
                if final_chips > 0:
                    # 存活奖励：给予一定的基础分，鼓励保本
                    score += 50 
                else:
                    # 破产惩罚：降低惩罚力度，避免过度保守
                    # 从 -500 改为 -100 (相当于输光买入)
                    # 这样 aggressive 的策略如果是 +EV 的，就不会被扼杀
                    score -= 100
                
                scores[idx] += score
                
            ptr += table_size
            
    return scores

def run_evolution(generations=100, pop_size=60):
    print(f"开始新版进化训练 (含生存奖励机制)...")
    print(f"种群大小: {pop_size}, 迭代代数: {generations}")
    
    population = [create_random_genome() for _ in range(pop_size)]
    best_genome_overall = None
    best_fitness_overall = -float('inf')
    
    # 记录历史最佳，用于最终分级
    hall_of_fame = []

    for gen in range(generations):
        fitness_scores = evaluate_fitness(population)
        
        # 统计本代最佳
        max_fitness = np.max(fitness_scores)
        best_idx = np.argmax(fitness_scores)
        
        if max_fitness > best_fitness_overall:
            best_fitness_overall = max_fitness
            best_genome_overall = population[best_idx]
            
        print(f"=== 第 {gen+1} 代 ===")
        print(f"本代最佳适应度 (净筹码): {max_fitness:.0f}")
        print(f"最佳基因: {population[best_idx]}")
        
        # 将本代前 5 名加入名人堂
        sorted_indices = np.argsort(fitness_scores)[::-1]
        for i in range(5):
            hall_of_fame.append(population[sorted_indices[i]])

        # 锦标赛选择 + 繁殖
        new_population = []
        
        # 精英保留 (Elitism): 保留前 2 名
        new_population.append(population[sorted_indices[0]])
        new_population.append(population[sorted_indices[1]])
        
        # 自适应变异率：随着代数增加，变异幅度减小
        progress = gen / generations
        current_scale = 0.2 * (1 - progress) + 0.02 # 0.2 -> 0.02
        
        while len(new_population) < pop_size:
            # 锦标赛选择
            candidates = random.sample(range(pop_size), 4)
            candidates_sorted = sorted(candidates, key=lambda i: fitness_scores[i], reverse=True)
            p1 = population[candidates_sorted[0]]
            p2 = population[candidates_sorted[1]]
            
            child = crossover(p1, p2)
            child = mutate(child, mutation_scale=current_scale)
            new_population.append(child)
            
        population = new_population

    print("\n=== 训练结束 ===")
    print(f"历史最佳适应度: {best_fitness_overall}")
    
    # 最终分级逻辑
    # 从名人堂中选出不同风格的代表
    # 我们根据 'fitness' 重新评估一次名人堂 (因为不同代次环境不同，直接比较不公平，但这里简化处理)
    # 或者我们直接按最终的 Population 分级
    
    rank_and_export_bots(hall_of_fame)

def rank_and_export_bots(candidates):
    print("\n开始分级评估 (最终考核)...")
    
    # 对候选人进行一次超大规模乱斗，确定真实座次
    # 这里我们简单地用最后一代的成绩，或者对名人堂进行一次大考
    # 为了节省时间，我们直接取名人堂的最后 50 个样本进行一次大乱斗
    
    final_pool = candidates[-50:] 
    scores = evaluate_fitness(final_pool, rounds_per_match=200) # 加大场次
    
    # 排序
    sorted_indices = np.argsort(scores)[::-1]
    
    # 分级 (按排名百分比)
    n = len(final_pool)
    
    presets = {}
    
    # Lv5 Legend: Top 1 (最强)
    idx = sorted_indices[0]
    presets["Lv5_Legend"] = final_pool[idx]
    
    # Lv4 Master: Top 20%
    idx = sorted_indices[int(n * 0.2)]
    presets["Lv4_Master"] = final_pool[idx]
    
    # Lv3 Experienced: Top 50%
    idx = sorted_indices[int(n * 0.5)]
    presets["Lv3_Experienced"] = final_pool[idx]
    
    # Lv2 Casual: Top 80%
    idx = sorted_indices[int(n * 0.8)]
    presets["Lv2_Casual"] = final_pool[idx]
    
    # Lv1 Rookie: Bottom 10% (最弱)
    idx = sorted_indices[int(n * 0.95)]
    presets["Lv1_Rookie"] = final_pool[idx]
    
    print("\n已生成 5 个档位的 AI 预设并写入 bot_presets.py:")
    content = "BOT_PRESETS = {\n"
    for name, genome in presets.items():
        print(f"  {name}: {genome}")
        content += f"    '{name}': {json.dumps(genome)},\n"
    content += "}\n"
    
    with open("bot_presets.py", "w", encoding='utf-8') as f:
        f.write(content)

if __name__ == "__main__":
    run_evolution(generations=100, pop_size=60)
