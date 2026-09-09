# 钓鱼（Fishing Poke Game）

本项目当前只维护 Godot 本地单机版，目标是通过可复现的学习与训练，最终得到真正强力、能够与人类玩家稳定对局的 AI Bot。

## 当前主线

- 产品形态：1 名真人玩家对战 1～5 个 Bot 的 Godot 4 单机游戏。
- 当前正式对手：使用冻结参数的 `LegacyGeneBot`。
- 规则实现、界面和 Bot 通过明确接口分层，便于未来训练、评测和替换策略。
- MVP 客户端已包含真实牌面、动态 2～6 人牌桌、发牌/筹码反馈、桌面音效与授权记录。
- 项目规则、Bot 状态、产品方向和开发指南统一从 [`docs/README.md`](docs/README.md) 查阅。

## 运行

```bash
godot --path godot_client
```

开发和测试命令见 [`docs/development/godot.md`](docs/development/godot.md)。

历史 Python、Web、Standalone 与实验性 Godot 实现仅保存在 `codex/archive-multi-implementation` 等历史分支中，不在当前主线维护。
