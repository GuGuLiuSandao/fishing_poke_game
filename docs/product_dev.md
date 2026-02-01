“钓鱼”图形界面与联机产品开发文档

1. 图形界面目标

提供沉浸式、直观的牌桌体验。

- **核心 UI 特性**：
  - **真实扑克牌展示**：采用 `deckofcardsapi.com` 提供的真实扑克牌图片。
  - **沉浸式搓牌模式 (Squeeze Mode)**：
    - 可通过左上角设置开启。
    - 开启后，发牌时仅显示第一张，第二张可通过点击“眼睛”按钮进入搓牌界面。
    - 支持拖拽搓牌和拇指遮挡模拟。
  - **动态座位布局**：根据玩家人数（2-6人）自动调整座位位置。
  - **历史记录 (History)**：
    - 每个人物头像旁显示最近一次行动气泡。
    - 下拉式菜单查看个人详细行动历史。
    - 全局对局记录弹窗 (Log)。
  - **智能操作按钮**：
    - 仅在轮到自己时显示可用按钮。
    - "下注" (Bet) 在跟注阶段自动变为 "带" (Dai/Call/Bet Pot)。
    - 增加 "下一局" (Ready) 按钮，支持全员弃牌或结算后快速开始。

支持桌面与移动端的基础适配（Tailwind CSS 响应式）。

2. 联机功能

- **WebSocket 实时同步**：
  - 游戏状态（Pot, Round, Turn）实时广播。
  - 玩家动作（Bet, Fold, Check）即时反馈。
  - 断线重连支持（基础）。

3. 账户与数据

- 账号体系：目前为临时 Session ID 或简单的 Name 输入。
- 数据记录：单局内的筹码变化实时显示。

4. 技术架构设计 (Technical Architecture)

采用**前后端分离 (Separation of Concerns)** 架构，确保前端交互的流畅性与后端服务的可扩展性。

4.1 总体架构
- **模式**：Client-Server (B/S)。
- **通信协议**：
  - **HTTP/REST**：用于非实时交互（用户登录、房间列表、战绩查询）。
  - **WebSocket**：用于游戏核心循环（发牌、下注、状态同步），保证毫秒级低延迟。

4.2 前端架构 (Frontend)
- **技术栈**：
  - **框架**：React 18+ (Functional Components + Hooks)。
  - **语言**：TypeScript (强类型保障游戏状态一致性)。
  - **构建工具**：Vite (提供极速的 HMR 开发体验)。
  - **状态管理**：Zustand (轻量级，适合管理 Game State, Player Info)。
  - **样式库**：Tailwind CSS (快速构建响应式布局)。
  - **网络层**：Axios (HTTP) + Native WebSocket / Socket.io-client。
- **目录规划 (`/web_client`)**：
  - `/src/components`: UI 组件 (Card, Chip, Avatar)。
  - `/src/game`: 游戏逻辑封装 (GameState, ActionTypes)。
  - `/src/hooks`: 自定义 Hooks (useWebSocket, useGameLoop)。
  - `/src/assets`: 静态资源。

4.3 后端架构 (Backend)
- **技术栈**：
  - **语言**：Python 3.11+。
  - **Web 框架**：FastAPI (高性能异步框架，原生支持 WebSocket)。
  - **数据模型**：Pydantic (用于请求验证和序列化)。
  - **并发模型**：Asyncio (处理多房间高并发)。
- **核心模块 (`/server` 或根目录)**：
  - `game_server.py`: WebSocket 连接管理、房间路由。
  - `chip_game.py`: 核心游戏状态机 (State Machine)。
  - `play_rule.py`: 牌型算法与胜负判定。
  - `bot_ai.py`: 机器人逻辑接口。

4.4 数据交互规范
- **WebSocket 消息格式 (JSON)**：
  - **Client -> Server**: `{ "action": "BET", "amount": 10, "uid": "user1" }`
  - **Server -> Client**: `{ "type": "STATE_UPDATE", "pot": 100, "turn": "user2", "events": [...] }`
- **类型同步**：尽量保持前端 TypeScript 接口与后端 Pydantic 模型的一致性。

5. 版本路线

- **v1.0 (MVP)**：
  - 完整 6 人局支持。
  - 核心玩法（发牌、比牌、底池逻辑）完备。
  - UI 美化（玻璃拟态、动画效果）。
  - 搓牌与历史记录增强体验。
  - **架构升级**：完成 React+Vite 重构。

- **v1.1 (Persistence)**：
  - 账号持久化 (SQLite/PostgreSQL)。
  - 战绩回放功能。

- **v2.0 (Polishing)**：
  - 更多动画特效（筹码飞入、发牌动画）。
  - 聊天系统与表情包。
