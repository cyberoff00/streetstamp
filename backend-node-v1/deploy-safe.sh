#!/bin/bash
# 安全部署脚本 - 包含备份和对比

set -e

SERVER_IP="101.132.159.73"
SERVER_USER="root"
REMOTE_DIR="/opt/streetstamps/backend-node-v1"
CONTAINER_NAME="streetstamps-node-v1"
BACKUP_DIR="/opt/streetstamps/backups/$(date +%Y%m%d_%H%M%S)"

echo "=========================================="
echo "StreetStamps Backend 安全部署"
echo "=========================================="
echo ""

# 1. 备份远程数据库
echo "📦 步骤 1/6: 备份 PostgreSQL 数据库..."
ssh ${SERVER_USER}@${SERVER_IP} << 'ENDSSH'
mkdir -p /opt/streetstamps/backups
BACKUP_FILE="/opt/streetstamps/backups/db_backup_$(date +%Y%m%d_%H%M%S).sql"
docker exec streetstamps-postgres pg_dump -U streetstamps streetstamps > "$BACKUP_FILE"
echo "✓ 数据库已备份到: $BACKUP_FILE"
ENDSSH

# 2. 备份远程代码
echo ""
echo "📦 步骤 2/6: 备份远程代码..."
ssh ${SERVER_USER}@${SERVER_IP} << ENDSSH
mkdir -p ${BACKUP_DIR}
cp -r ${REMOTE_DIR}/server.js ${BACKUP_DIR}/
cp -r ${REMOTE_DIR}/package.json ${BACKUP_DIR}/
cp -r ${REMOTE_DIR}/package-lock.json ${BACKUP_DIR}/
echo "✓ 代码已备份到: ${BACKUP_DIR}"
ENDSSH

# 3. 对比文件差异
echo ""
echo "🔍 步骤 3/6: 对比文件差异..."
echo "--- server.js 差异 ---"
ssh ${SERVER_USER}@${SERVER_IP} "cat ${REMOTE_DIR}/server.js" > /tmp/remote_server.js
diff -u /tmp/remote_server.js backend-node-v1/server.js | head -50 || true
echo ""
read -p "是否继续部署？(yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "❌ 部署已取消"
    exit 1
fi

# 4. 上传新文件
echo ""
echo "📤 步骤 4/6: 上传新文件..."
scp backend-node-v1/server.js ${SERVER_USER}@${SERVER_IP}:${REMOTE_DIR}/server.js.new
scp backend-node-v1/package.json ${SERVER_USER}@${SERVER_IP}:${REMOTE_DIR}/package.json.new
scp backend-node-v1/package-lock.json ${SERVER_USER}@${SERVER_IP}:${REMOTE_DIR}/package-lock.json.new
scp backend-node-v1/migrate-to-relational.sql ${SERVER_USER}@${SERVER_IP}:${REMOTE_DIR}/
scp backend-node-v1/migrate-data.js ${SERVER_USER}@${SERVER_IP}:${REMOTE_DIR}/
scp backend-node-v1/SECURITY-FIXES.md ${SERVER_USER}@${SERVER_IP}:${REMOTE_DIR}/
echo "✓ 文件上传完成"

# 5. 安装依赖并替换文件
echo ""
echo "🔧 步骤 5/6: 安装 bcrypt 依赖..."
ssh ${SERVER_USER}@${SERVER_IP} << ENDSSH
cd ${REMOTE_DIR}
# 先安装bcrypt
npm install bcrypt
# 替换文件
mv server.js.new server.js
mv package.json.new package.json
mv package-lock.json.new package-lock.json
echo "✓ 文件已替换"
ENDSSH

# 6. 重启容器
echo ""
echo "🔄 步骤 6/6: 重启 Docker 容器..."
ssh ${SERVER_USER}@${SERVER_IP} << ENDSSH
docker restart ${CONTAINER_NAME}
sleep 5
# 检查健康状态
docker logs ${CONTAINER_NAME} --tail 20
echo ""
echo "检查健康端点..."
curl -s http://localhost:18080/v1/health | jq .
ENDSSH

echo ""
echo "=========================================="
echo "✅ 部署完成！"
echo "=========================================="
echo ""
echo "备份位置: ${BACKUP_DIR}"
echo ""
echo "⚠️  重要提示："
echo "1. 旧用户首次登录会自动升级密码哈希"
echo "2. 监控日志确认无错误"
echo "3. 如有问题，运行回滚脚本"
echo ""
