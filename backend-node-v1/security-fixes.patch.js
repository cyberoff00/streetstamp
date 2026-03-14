// 安全修复补丁
// 1. 密码哈希改bcrypt
// 2. 并发写入保护
// 3. 显示名称索引优化
// 4. 降低body limit

const bcrypt = require("bcrypt");

// ============ 1. 密码哈希 ============
const BCRYPT_ROUNDS = 10;

async function hashPasswordSecure(password) {
  return await bcrypt.hash(password, BCRYPT_ROUNDS);
}

async function verifyPasswordSecure(password, hash) {
  return await bcrypt.compare(password, hash);
}

// ============ 2. 并发写入保护 ============
class DBWriteLock {
  constructor() {
    this.locked = false;
    this.queue = [];
  }

  async acquire() {
    if (!this.locked) {
      this.locked = true;
      return;
    }
    await new Promise(resolve => this.queue.push(resolve));
  }

  release() {
    this.locked = false;
    const next = this.queue.shift();
    if (next) {
      this.locked = true;
      next();
    }
  }

  async withLock(fn) {
    await this.acquire();
    try {
      return await fn();
    } finally {
      this.release();
    }
  }
}

const dbWriteLock = new DBWriteLock();

async function saveDBSafe(db, saveFn) {
  return await dbWriteLock.withLock(async () => {
    await saveFn(db);
  });
}

// ============ 3. 显示名称索引 ============
class DisplayNameIndex {
  constructor() {
    this.nameToUserID = new Map();
  }

  rebuild(users) {
    this.nameToUserID.clear();
    for (const [uid, user] of Object.entries(users || {})) {
      const name = this.normalize(user?.displayName);
      if (name) {
        this.nameToUserID.set(name, uid);
      }
    }
  }

  normalize(raw) {
    const trimmed = String(raw || "").trim();
    return trimmed || "Explorer";
  }

  canUse(displayName, excludedUserID = "") {
    const name = this.normalize(displayName);
    const owner = this.nameToUserID.get(name);
    return !owner || owner === excludedUserID;
  }

  allocate(displayName, excludedUserID = "") {
    const base = this.normalize(displayName);
    if (this.canUse(base, excludedUserID)) return base;

    for (let suffix = 2; suffix < 10000; suffix++) {
      const candidate = `${base}${suffix}`;
      if (this.canUse(candidate, excludedUserID)) return candidate;
    }
    return `${base}${Date.now()}`;
  }

  set(displayName, userID) {
    const name = this.normalize(displayName);
    this.nameToUserID.set(name, userID);
  }

  delete(displayName) {
    const name = this.normalize(displayName);
    this.nameToUserID.delete(name);
  }
}

module.exports = {
  hashPasswordSecure,
  verifyPasswordSecure,
  DBWriteLock,
  dbWriteLock,
  saveDBSafe,
  DisplayNameIndex
};
