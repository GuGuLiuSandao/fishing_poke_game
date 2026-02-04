Write-Host "=================================="
Write-Host "      Trae 钓鱼游戏启动脚本"
Write-Host "=================================="

# 1. 启动后端
Write-Host "`n[1/2] 正在启动后端服务器..."
# 使用 cmd /k 保持窗口打开，以便查看错误日志
Start-Process -FilePath "cmd" -ArgumentList "/k cd server && python game_server.py" -WindowStyle Minimized

# 2. 启动前端
Write-Host "`n[2/2] 正在启动前端客户端..."
Set-Location "web_client"

# 检查依赖
if (-not (Test-Path "node_modules")) {
    Write-Host "检测到 node_modules 不存在，正在安装依赖..."
    npm install
}

Write-Host "正在启动 Vite 开发服务器..."
npm run dev
