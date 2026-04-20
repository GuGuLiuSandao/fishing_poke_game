# godot_client

这是 `fishing_poke_game` 的 Godot 客户端原型。

## 现在做到了什么

- 可打开的 Godot 4 项目
- 一个可交互的牌桌界面
- Start / Next Turn / Reset 三个按钮
- 4 个座位的状态展示

## 目录

- `project.godot`：项目入口
- `scenes/Main.tscn`：主场景
- `scripts/main.gd`：桌面状态逻辑

## 启动

```bash
godot --path godot_client
```

## 下一步

1. 把座位和桌面数据拆成独立组件。
2. 接上真实规则层。
3. 再把 WebSocket 联机接进来。
