# 数据隔离漏洞修复 - 部署指南

## 问题
不同用户的journeys数据发生串数据，例如：
- 1511127208@qq.com 的杭州数据进入了 dongsangrou@foxmail.com
- 美国数据也错误地进入了 dongsangrou@foxmail.com

## 修复内容
已修改 server.js 的3处代码，强制在服务端设置 ownerUserID，防止数据串。

## 部署步骤

### 1. 上传文件到服务器
将以下文件上传到后端目录：
- server.js
- fix-postgres-data-isolation.js (PostgreSQL用)
- remove-cross-user-journeys.js (文件存储用)

### 2. 在服务器执行

#### 如果使用PostgreSQL：
```bash
cd /path/to/backend
node fix-postgres-data-isolation.js
pkill -f "node.*server.js"
nohup node server.js > server.log 2>&1 &
```

#### 如果使用文件存储：
```bash
cd /path/to/backend
node remove-cross-user-journeys.js
pkill -f "node.*server.js"
nohup node server.js > server.log 2>&1 &
```

### 3. 验证
```bash
tail -f server.log
```

看到 `[streetstamps-node-v1] listening on :18080` 即成功。

## 重要提示
- 修复脚本会自动备份数据
- 修复后用户下次同步时会自动设置正确的 ownerUserID
- 建议立即部署，避免数据继续串
