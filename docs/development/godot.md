# Godot 客户端开发指南

这是 `fishing_poke_game` 的完整本地单机客户端，不依赖 Python 服务端或 WebSocket。

## 现在做到了什么

- 可打开的 Godot 4 项目
- 1 名真人玩家对战 1～5 个 Bot
- 可选择 Bot 数量
- 完整实现 [`docs/rules/game-rules.md`](../rules/game-rules.md) 中的 32 张牌、牌力、补底、下注、吃、带、过牌、弃牌、捡天水、平局和结算规则
- 完整整场流程：连续多局、淘汰、胜负、下一局与重新开始
- 2～6 人牌桌、玩家自选下注金额、逐个展示的 Bot 行动和牌局记录
- CC0 牌面和牌背，可选手动看牌，可关闭发牌、翻牌和筹码动画及桌面音效
- 所有对手使用已经冻结参数的 `LegacyGeneBot`
- Bot 只能读取自己的手牌和公开状态，并通过统一合法动作接口行动

## 目录

- `project.godot`：项目入口
- `scenes/Main.tscn`：主场景
- `scripts/main.gd`：主场景、牌桌流程、设置与记录面板
- `scripts/ui/`：桌面、座位、筹码表现、下注操作区与主题
- `assets/`：牌面、音效与对应第三方授权记录；来源见 [`ui-mvp.md`](ui-mvp.md)
- `scripts/game/hand_rules.gd`：牌组、牌型与牌力比较
- `scripts/game/game_rules.gd`：补底、信用与结算公式
- `scripts/game/bot_contract.gd`：Bot 公开观察、合法动作和决策契约
- `scripts/game/legacy_gene_bot.gd`：当前正式对手的固定遗传策略
- `scripts/game/random_bot.gd`：自动评测使用的随机基线
- `scripts/game/round_simulator.gd`：可克隆、可逐步执行的纯数据局内模拟器
- `scripts/game/bot_policy.gd`：GeneBot 优化评测使用的固定启发式基线
- `scripts/game/local_game.gd`：整场单机状态机
- `tests/`：规则、行动、整场模拟与 UI 冒烟测试
- `tools/optimize_gene_bot.gd`：可复现的离线遗传优化与独立评测工具

## 启动

```bash
godot --path godot_client
```

## 验证

规则基准按 [玩法规则](../rules/game-rules.md) 的章节运行。牌组清单、牌力顺序和固定对局预期直接按文档编写。每个固定对局逐步核对 Godot 整场状态机与纯模拟器，分别与预期结果比较。基准穷举 496 种手牌和 246,016 次有序比较，并检查 2～6 人开局、补底边界、合法动作、各类结算、手牌公开、先手与淘汰。失败时输出预期和实际结果，并以非零状态退出。

```bash
godot --headless --path godot_client --script res://tests/rule_baseline.gd
```

界面看牌、下注输入和各人数布局由 `ui_smoke.gd` 覆盖。真实窗口的鼠标回放命令见下方。

```bash
godot --headless --path godot_client --script res://tests/local_game_smoke.gd
godot --headless --path godot_client --script res://tests/legacy_gene_bot_test.gd
godot --headless --path godot_client --script res://tests/bot_foundation_test.gd
godot --headless --path godot_client --script res://tests/playthrough_20_rounds.gd
godot --headless --path godot_client --script res://tests/rules_test.gd
godot --headless --path godot_client --script res://tests/player_actions_smoke.gd
godot --headless --path godot_client --script res://tests/settlement_test.gd
godot --headless --path godot_client --script res://tests/ui_smoke.gd
godot --headless --path godot_client --quit-after 1
```

GeneBot 优化器接口冒烟测试：

```bash
godot --headless --path godot_client --script res://tools/optimize_gene_bot.gd -- --smoke
```

真实窗口鼠标回放需要显示窗口，不能使用 `--headless`，也不要与其他 Godot 测试并行运行：

```bash
godot --path godot_client --script res://tests/ui_mouse_playthrough_20_rounds.gd
```

使用实际渲染窗口生成入座、四人桌、紧凑六人桌、牌局记录与结算截图：

```bash
godot --path godot_client --script res://tests/capture_ui.gd -- /tmp/fishing-table-preview
```
