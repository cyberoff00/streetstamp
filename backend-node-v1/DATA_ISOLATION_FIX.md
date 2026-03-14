# 数据隔离问题修复指南

## 问题描述

发现严重的数据隔离漏洞：不同用户的 journeys 数据发生了串数据。例如：
- 1511127208@qq.com 的杭州数据进入了 dongsangrou@foxmail.com
- 美国数据也错误地进入了 dongsangrou@foxmail.com

## 根本原因

在 `server.js` 的 `/v1/journeys/migrate` 接口中，后端直接接受客户端传来的 journeys 数据，**没有验证这些 journeys 是否属于当前登录用户**。

## 修复步骤

### 1. 停止后端服务
```bash
# 停止正在运行的后端
pkill -f "node.*server.js"
```

### 2. 备份当前数据
```bash
cd backend-node-v1
cp data/data.json data/data.json.backup.$(date +%s)
```

### 3. 运行数据清理脚本
```bash
# 移除错误的跨用户journeys
node remove-cross-user-journeys.js
```

### 4. 重启后端服务
```bash
node server.js
```

### 5. 通知用户重新同步
已修复的代码会在用户下次同步时自动设置正确的 ownerUserID。

## 代码修复说明

已修改的文件：`server.js`

1. **normalizeJourneyPayload** - 添加 ownerUserID 参数并强制设置
2. **mergeJourneyPayloads** - 传递 ownerUserID 到 normalize 函数
3. **/v1/journeys/migrate** - 调用时传入当前用户的 uid

## 验证修复

运行清理脚本后，检查输出：
- 如果显示移除了journeys，说明确实存在数据串的问题
- 备份文件会自动创建在 `data/data.json.backup.{timestamp}`
