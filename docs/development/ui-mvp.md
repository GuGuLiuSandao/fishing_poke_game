# Godot 牌桌界面

本文档记录单机牌桌的交互、参考来源与第三方素材授权。玩法仍以 [`../rules/game-rules.md`](../rules/game-rules.md) 为唯一权威来源。

## 牌桌交互

- 入座前选择 1～5 名对手，默认 3 名。真人固定坐在桌子下方，其他玩家依顺时针顺序落座。圆形「先」牌标记本局先手。
- 当前行动者的席位用金色边框标记。Bot 逐个行动，筹码和最近动作显示在对应席位上。牌桌中央显示桌上的底数，顶部「牌局记录」可查看本场记录。
- 第一次行动在底部选择弃牌或下注。下注金额默认留空，玩家拖动滑杆或输入整数后再确认。金额恰好等于当前底池时，确认按钮显示「吃」。下注后的再次行动可以过牌，满足筹码条件时才显示「带」和该次应付的底数。
- 结算停留在原牌桌上，显示结果、收取金额和留给下局的底池。只有玩法要求公开的手牌才正面显示。玩家确认「下一局」后发牌。
- 「玩法」可以随时打开。「设置」可关闭声音和动画，也可选择每局手动看牌。打开面板时暂停 Bot 行动，关闭后继续。

## 扑克客户端参考

- 围绕桌面的座位、底部的行动按钮和自选金额的滑杆参考 [PokerStars 牌桌](https://www.pokerstars.com/poker/room/features/software-news/)。
- 自己的牌可以选择发完即开或手动翻开。参考 [GGPoker 手动看牌](https://legal.ggpoker.com/poker-games/table-social-features/)。
- [partypoker 牌桌与牌局回放](https://www.partypoker.com/en/poker/p/software-updates)。结果留在桌上，直接关联玩家席位和手牌。
- 桌布、桌沿和筹码由 Godot 绘制。牌面、牌背和声音使用下面列出的 CC0 素材。

## 第三方素材

### 牌面

- 名称：[Cards Set](https://opengameart.org/content/cards-set)
- 作者：Sylly
- 授权：CC0 1.0
- 本项目用途：`godot_client/assets/cards/` 中的牌面与蓝色牌背。
- 本地授权记录：`godot_client/assets/licenses/cards-set-cc0.txt`

### 音效

- 名称：[54 Casino Sound Effects](https://opengameart.org/content/54-casino-sound-effects-cards-dice-chips)
- 作者：Kenney
- 授权：CC0 1.0
- 本项目用途：洗牌、发牌、弃牌、放置筹码和筹码结算音效。
- 本地授权记录：`godot_client/assets/licenses/kenney-casino-audio.txt`

CC0 不要求署名，但发布版本仍应在制作人员或关于页面保留素材名称、作者与来源，方便后续审计。

## 验证

- 默认窗口为 1440×810，最小窗口为 1024×600。检查 2～6 人座位、手牌和行动区有无重叠。
- 验证滑杆和手动输入只调整下注金额，确认后才提交。确认时按规则区分「下注」与「吃」，筹码不足以带时只显示过牌。
- 核对比牌、打跑其他玩家、捡天水成功或失败和平局时的公开手牌、筹码和底池展示。
- 运行[开发指南](godot.md)中的 UI 冒烟、20 局鼠标回放和规则测试。发布包保留 `assets/licenses/` 中的授权记录。
