# Godot 界面 MVP

本文档记录当前单机版的界面方向、实现参考与第三方素材授权。玩法仍以 [`../rules/game-rules.md`](../rules/game-rules.md) 为唯一权威来源。

## 体验目标

- 牌桌是第一视觉焦点，设置、行动与日志集中在右侧控制台。
- 手牌必须以真实牌面呈现；未公开的 Bot 手牌只显示统一牌背。
- 当前行动者、底池、可选行动和局内结算必须一眼可辨。
- 发牌、投入筹码、弃牌和结算使用短促动效与音效提供反馈，不阻塞规则状态机。
- 2～6 人布局共用同一套顺时针座位算法，真人固定显示在画面下方。
- 音效可以随时关闭，关闭不影响玩法。

## 实现参考

- [Veneno](https://github.com/BananaHolograma/Veneno)：Godot 4、MIT；参考其单机卡牌桌面、AI 对局和实体牌面呈现。
- [Card Framework](https://github.com/chun92/card-framework)：Godot 4、MIT；参考其牌面容器、发牌动画和悬停反馈。项目没有引入该框架，以免让通用卡牌交互侵入现有规则层。
- [Godot Card Game Framework](https://github.com/db0/godot-card-game-framework)：AGPL-3.0；仅研究其移动、高亮和手牌排列思路，没有复制代码或资源。

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

## MVP 验收

- 默认 4 人局与最大 6 人局均无座位遮挡或关键操作溢出。
- 只有真人与规则要求公开的玩家能看到牌面。
- “下注 / 吃 / 弃牌 / 过牌 / 带 / 下一局 / 重新开始”的显示条件与规则状态一致。
- 音效开关可用，所有音效均来自仓库内资源，不依赖网络。
- UI 冒烟、20 局鼠标回放和全部规则测试通过。
- 发布包包含 `assets/licenses/` 中的授权记录。
