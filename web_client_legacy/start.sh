#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 定义清理函数
cleanup() {
    echo ""
    echo "正在关闭游戏服务..."
    if [ -n "$SERVER_PID" ]; then
        kill $SERVER_PID 2>/dev/null
        echo "后端服务器已停止"
    fi
    exit
}

# 捕获 Ctrl+C (SIGINT) 和 终止信号 (SIGTERM)
trap cleanup SIGINT SIGTERM

echo "=================================="
echo "        钓鱼游戏启动脚本"
echo "=================================="

# 1. 启动后端
echo ""
echo "[1/2] 正在启动后端服务器..."
cd "$PROJECT_ROOT/server"
# 后台运行 python，不产生 __pycache__
export PYTHONDONTWRITEBYTECODE=1
python3 game_server.py &
SERVER_PID=$!
echo "后端运行中 (PID: $SERVER_PID)"

# 等待几秒确保后端端口就绪
sleep 2

# 2. 启动前端
echo ""
echo "[2/2] 正在启动前端客户端..."
cd "$PROJECT_ROOT/web_client"

# 检查是否需要安装依赖
if [ ! -d "node_modules" ]; then
    echo "检测到 node_modules 不存在，正在安装依赖..."
    npm install
fi

echo "正在启动 Vite 开发服务器..."
npm run dev

# 如果 npm run dev 退出（例如发生错误），则执行清理
cleanup
