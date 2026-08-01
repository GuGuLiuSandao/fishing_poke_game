# godot_client

这是 `fishing_poke_game` 的完整本地单机客户端，不依赖 Python 服务端或 WebSocket。

## 现在做到了什么

- 可打开的 Godot 4 项目
- 1 名真人玩家对战 1～5 个 Bot
- 可选择 Bot 数量和难度
- 完整实现根目录 `RULES.md` 中的 32 张牌、牌力、补底、下注、吃、带、过牌、弃牌、捡天水、平局和结算规则
- 完整整场流程：连续多局、淘汰、胜负、下一局与重新开始
- 动态 2～6 人牌桌、隐藏信息和对局日志
- 轻松难度使用固定遗传策略，标准和老练难度使用后台 Monte Carlo Rollout 搜索
- 可取消的 100ms / 500ms 搜索预算，重新开始不会等待旧搜索

## 目录

- `project.godot`：项目入口
- `scenes/Main.tscn`：主场景
- `scripts/main.gd`：桌面 UI、动态座位和交互
- `scripts/game/hand_rules.gd`：牌组、牌型与牌力比较
- `scripts/game/game_rules.gd`：补底、信用与结算公式
- `scripts/game/bot_contract.gd`：Bot 公开观察、合法动作和决策契约
- `scripts/game/legacy_gene_bot.gd`：简单难度的固定遗传策略
- `scripts/game/random_bot.gd`：自动评测使用的随机基线
- `scripts/game/round_simulator.gd`：可克隆、可逐步执行的纯数据局内模拟器
- `scripts/game/search_bot.gd`：标准和老练难度的 Rollout SearchBot
- `scripts/game/search_job.gd`：后台搜索任务与线程安全结果传递
- `scripts/game/bot_policy.gd`：仅供历史 GeneBot 优化评测使用
- `scripts/game/local_game.gd`：整场单机状态机
- `tests/`：规则、行动、整场模拟与 UI 冒烟测试
- `tools/optimize_gene_bot.gd`：可复现的离线遗传优化与独立评测工具
- `tools/benchmark_bots.gd`：固定种子、全座位轮换 Bot 交叉评测

## 启动

```bash
godot --path godot_client
```

## 验证

```bash
godot --headless --path godot_client --script res://tests/local_game_smoke.gd
godot --headless --path godot_client --script res://tests/legacy_gene_bot_test.gd
godot --headless --path godot_client --script res://tests/search_bot_test.gd
godot --headless --path godot_client --script res://tests/search_performance_test.gd
godot --headless --path godot_client --script res://tests/search_cancellation_test.gd
godot --headless --path godot_client --script res://tests/playthrough_20_rounds.gd
godot --headless --path godot_client --script res://tests/rules_test.gd
godot --headless --path godot_client --script res://tests/player_actions_smoke.gd
godot --headless --path godot_client --script res://tests/settlement_test.gd
godot --headless --path godot_client --script res://tests/ui_smoke.gd
godot --headless --path godot_client --quit-after 1
```

完整 Bot 交叉评测耗时较长：

```bash
godot --headless --path godot_client --script res://tools/benchmark_bots.gd
```

GeneBot 优化器接口冒烟测试：

```bash
godot --headless --path godot_client --script res://tools/optimize_gene_bot.gd -- --smoke
```

真实窗口鼠标回放需要显示窗口，不能使用 `--headless`，也不要与其他 Godot 测试并行运行：

```bash
godot --path godot_client --script res://tests/ui_mouse_playthrough_20_rounds.gd
```
