const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || "postgresql://streetstamps:streetstamps@localhost:5432/streetstamps"
});

(async () => {
  console.log("🗑️  删除示例journeys...\n");

  const result = await pool.query("SELECT state FROM app_state WHERE key = $1", ["global"]);
  const db = result.rows[0].state;

  const exampleJourneyIDs = ["j_public", "j_friends", "j_private"];
  let deleted = 0;

  for (const [uid, user] of Object.entries(db.users || {})) {
    if (!Array.isArray(user.journeys)) continue;

    const before = user.journeys.length;
    user.journeys = user.journeys.filter(j => !exampleJourneyIDs.includes(j.id));
    const removed = before - user.journeys.length;

    if (removed > 0) {
      console.log(`${user.email || user.displayName}: 删除 ${removed} 个示例journeys`);
      deleted += removed;
    }
  }

  if (deleted === 0) {
    console.log("✅ 没有找到示例journeys");
    await pool.end();
    return;
  }

  console.log(`\n💾 保存修复后的数据...`);
  await pool.query("UPDATE app_state SET state = $1 WHERE key = $2", [db, "global"]);
  console.log(`✅ 已删除 ${deleted} 个示例journeys`);

  await pool.end();
})();
