#!/bin/bash
# 快速部署 - 复制粘贴每个命令块执行

echo "=== 步骤1: 登录服务器 ==="
echo "ssh root@101.132.159.73"
echo "密码: Ylinteresting22@"
echo ""
echo "=== 步骤2: 执行以下命令备份 ==="
cat << 'EOF'
# 备份数据库
mkdir -p /opt/streetstamps/backups
docker exec streetstamps-postgres pg_dump -U streetstamps streetstamps > /opt/streetstamps/backups/db_$(date +%Y%m%d_%H%M%S).sql

# 备份代码
BACKUP_DIR=/opt/streetstamps/backups/code_$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR
cp /opt/streetstamps/backend-node-v1/server.js $BACKUP_DIR/
cp /opt/streetstamps/backend-node-v1/package.json $BACKUP_DIR/
echo "备份完成: $BACKUP_DIR"
EOF

echo ""
echo "=== 步骤3: 在本地新终端上传文件 ==="
cat << EOF
cd $(pwd)
scp server.js root@101.132.159.73:/opt/streetstamps/backend-node-v1/server.js.new
scp package.json root@101.132.159.73:/opt/streetstamps/backend-node-v1/package.json.new
scp package-lock.json root@101.132.159.73:/opt/streetstamps/backend-node-v1/package-lock.json.new
EOF

echo ""
echo "=== 步骤4: 回到服务器执行 ==="
cat << 'EOF'
cd /opt/streetstamps/backend-node-v1
npm install bcrypt
mv server.js.new server.js
mv package.json.new package.json
mv package-lock.json.new package-lock.json
docker restart streetstamps-node-v1
sleep 5
docker logs streetstamps-node-v1 --tail 30
curl http://localhost:18080/v1/health
EOF
