@echo off
setlocal
title Fishing Game Launcher

echo ==================================
echo         钓鱼游戏启动脚本
echo ==================================

:: 1. 启动后端
echo.
echo [1/2] 正在启动后端服务器...
:: 使用 start 命令新开一个窗口运行服务器，避免阻塞当前窗口
:: /MIN 最小化窗口
start "Diaoyu Game Server" /MIN cmd /c "cd /d ""%~dp0..\server"" && python game_server.py"

:: 2. 启动前端
echo.
echo [2/2] 正在启动前端客户端...
cd /d "%~dp0..\web_client"

:: 检查依赖
if not exist node_modules (
    echo 检测到未安装依赖，正在执行 npm install...
    call npm install
)

echo 正在启动 Vite 开发服务器...
call npm run dev

:: 退出时提示
echo.
echo 前端服务已停止。请手动关闭后端的 Server 窗口（如果未自动关闭）。
pause
