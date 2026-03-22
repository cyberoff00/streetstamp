const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || "postgresql://streetstamps:streetstamps@localhost:5432/streetstamps"
});

(async () => {
  console.log("🔍 开始清理重复journeys...\n");

  const result = await pool.query("SELECT state FROM app_state WHERE key = $1", ["global"]);
  const db = result.rows[0].state;

  // 统计每个journey属于哪些用户
  const journeyOwners = new Map();
  for (const [uid, user] of Object.entries(db.users || {})) {
    if (!Array.isArray(user.journeys)) continue;
    for (const j of user.journeys) {
      if (!journeyOwners.has(j.id)) {
        journeyOwners.set(j.id, []);
      }
      journeyOwners.get(j.id).push(uid);
    }
  }

  // 找出重复的
  const duplicates = Array.from(journeyOwners.entries()).filter(([_, owners]) => owners.length > 1);

  console.log(`总journeys: ${journeyOwners.size}`);
  console.log(`重复的: ${duplicates.length}\n`);

  if (duplicates.length === 0) {
    console.log("✅ 没有重复journeys");
    await pool.end();
    return;
  }

  // 清理策略：保留最早注册的用户（根据用户createdAt）
  let cleaned = 0;
  for (const [jid, owners] of duplicates) {
    // 找出注册最早的用户
    let earliestUser = owners[0];
    let earliestTime = db.users[owners[0]].createdAt || Infinity;

    for (const uid of owners) {
      const userTime = db.users[uid].createdAt || Infinity;
      if (userTime < earliestTime) {
        earliestTime = userTime;
        earliestUser = uid;
      }
    }

    const removeUsers = owners.filter(uid => uid !== earliestUser);

    console.log(`Journey ${jid}:`);
    console.log(`  保留: ${db.users[earliestUser]?.email || db.users[earliestUser]?.displayName} (最早注册用户)`);

    for (const uid of removeUsers) {
      const user = db.users[uid];
      user.journeys = user.journeys.filter(j => j.id !== jid);
      console.log(`  删除: ${user.email || user.displayName}`);
      cleaned++;
    }
  }

  console.log(`\n💾 保存修复后的数据...`);
  await pool.query("UPDATE app_state SET state = $1 WHERE key = $2", [db, "global"]);
  console.log(`✅ 已清理 ${cleaned} 个重复journeys`);

  await pool.end();
})();
