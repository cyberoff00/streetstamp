#!/bin/bash
set -e

SERVER="root@101.132.159.73"
REMOTE_PATH="/root/backend-node-v1"

echo "📦 上传修复文件到服务器..."
scp server.js remove-cross-user-journeys.js DATA_ISOLATION_FIX.md $SERVER:$REMOTE_PATH/

echo "🔧 在服务器上执行修复..."
ssh $SERVER << 'ENDSSH'
cd /root/backend-node-v1

# 备份数据
echo "💾 备份数据..."
cp data/data.json data/data.json.backup.$(date +%s)

# 清理错误数据
echo "🧹 清理跨用户数据..."
node remove-cross-user-journeys.js

# 重启服务
echo "🔄 重启服务..."
pm2 restart streetstamps || pm2 restart all || (pkill -f "node.*server.js" && nohup node server.js > server.log 2>&1 &)

echo "✅ 部署完成！"
ENDSSH

echo "✅ 修复已部署到线上服务器"
