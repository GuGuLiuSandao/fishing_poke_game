# godot_client

这是给 `fishing_poke_game` 新开的 Godot 客户端骨架。

## 现在有什么

- `project.godot`：Godot 4 项目入口
- `scenes/Main.tscn`：启动主场景
- `scripts/main.gd`：当前占位逻辑

## 目录规划

- `scenes/`：场景
- `scripts/`：GDScript
- 后面建议再补：
  - `assets/`：图片/音效
  - `ui/`：可复用 UI 组件
  - `network/`：WebSocket 客户端
  - `core/`：如果后面把规则层迁进来，可以放这里

## 本地打开

```bash
godot --path godot_client
```

或者直接双击导入 `godot_client/project.godot`。

## 下一步建议

1. 先把单机桌面原型做出来：牌桌、玩家位、回合状态。
2. 然后接 WebSocket，把现在 Python 服务端先复用起来。
3. 最后再考虑把核心规则和 Bot 抽成 Godot/Python 共用边界。
