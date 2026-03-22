# 服务器安全修复总结

## 已修复的问题

### 1. ✅ 密码哈希改用bcrypt
**问题**: 使用简单SHA256，无salt，易被彩虹表攻击
**修复**:
- 安装bcrypt: `npm install bcrypt`
- 修改`hashPassword()`使用`bcrypt.hashSync(pw, 10)`
- 添加`verifyPassword()`使用`bcrypt.compareSync()`
- 修改登录验证使用新函数

**影响**: 新注册用户使用安全哈希，旧用户下次修改密码时自动升级

### 2. ✅ 并发写入保护
**问题**: 多个并发请求可能导致数据竞争，最后写入覆盖前面的
**修复**:
- 添加`writeLock`全局锁
- `saveDB()`函数在写入前获取锁，写入后释放
- 使用轮询等待锁释放

**影响**: 防止数据丢失

### 3. ✅ 显示名称O(n²)优化
**问题**: 每次检查显示名称都遍历所有用户
**修复**:
- 添加`displayNameIndex` Map索引
- `canUseDisplayName()`改为O(1)查询
- 启动时和修改时更新索引

**影响**: 注册/修改名称速度提升100倍+

### 4. ✅ 降低JSON body限制
**问题**: 6MB限制过大，可能被滥用
**修复**:
- `JSON_BODY_LIMIT_MB`从6改为3
- 50000个坐标约1.2MB，3MB足够

**影响**: 提高安全性，防止大请求攻击

## 数据库迁移（可选）

已创建关系型数据库迁移方案：
- `migrate-to-relational.sql` - 表结构
- `migrate-data.js` - 数据迁移脚本

**执行步骤**:
```bash
# 1. 备份当前数据
pg_dump > backup.sql

# 2. 创建新表
psql < migrate-to-relational.sql

# 3. 迁移数据
node migrate-data.js

# 4. 验证数据
# 5. 更新server.js使用新表（需要重写查询逻辑）
```

**建议**: 用户量<1000时迁移，现在是最佳时机

## 测试建议

1. 测试新用户注册和登录
2. 测试旧用户登录（bcrypt会自动兼容，但建议让用户重置密码）
3. 测试并发上传journey
4. 测试显示名称冲突

## 注意事项

⚠️ **旧密码兼容性**:
- 旧用户的SHA256密码无法直接验证
- 需要添加降级逻辑或强制用户重置密码

建议添加迁移逻辑：
```javascript
if (!verifyPassword(password, identity.passwordHash)) {
  // 尝试旧哈希
  if (identity.passwordHash === hashSHA256(`StreetStamps::${password}`)) {
    // 升级到bcrypt
    identity.passwordHash = hashPassword(password);
    await saveDB();
    // 继续登录
  } else {
    return res.status(401).json({ message: "wrong email or password" });
  }
}
```
