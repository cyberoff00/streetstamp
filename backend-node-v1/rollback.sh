#!/bin/bash
# 回滚脚本

set -e

SERVER_IP="101.132.159.73"
SERVER_USER="root"
REMOTE_DIR="/opt/streetstamps/backend-node-v1"
CONTAINER_NAME="streetstamps-node-v1"

echo "请输入备份目录路径 (例如: /opt/streetstamps/backups/20260314_170000):"
read BACKUP_DIR

echo "🔄 开始回滚..."

ssh ${SERVER_USER}@${SERVER_IP} << ENDSSH
cd ${REMOTE_DIR}
cp ${BACKUP_DIR}/server.js ./server.js
cp ${BACKUP_DIR}/package.json ./package.json
cp ${BACKUP_DIR}/package-lock.json ./package-lock.json
docker restart ${CONTAINER_NAME}
echo "✅ 回滚完成"
ENDSSH
