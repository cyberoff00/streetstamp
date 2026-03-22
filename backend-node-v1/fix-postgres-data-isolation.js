const { Pool } = require("pg");

const DATABASE_URL = process.env.DATABASE_URL || "";
const PGHOST = process.env.PGHOST || "";
const PGPORT = Number(process.env.PGPORT || 5432);
const PGUSER = process.env.PGUSER || "";
const PGPASSWORD = process.env.PGPASSWORD || "";
const PGDATABASE = process.env.PGDATABASE || "";
const PG_STATE_KEY = process.env.PG_STATE_KEY || "global";

let pool;
if (DATABASE_URL) {
  pool = new Pool({ connectionString: DATABASE_URL, ssl: { rejectUnauthorized: false } });
} else if (PGHOST && PGUSER && PGDATABASE) {
  pool = new Pool({ host: PGHOST, port: PGPORT, user: PGUSER, password: PGPASSWORD, database: PGDATABASE });
} else {
  console.error("❌ 未配置PostgreSQL连接");
  process.exit(1);
}

async function main() {
  console.log("🔍 检查PostgreSQL数据隔离问题...\n");

  const result = await pool.query("SELECT state FROM app_state WHERE key = $1", [PG_STATE_KEY]);
  if (!result.rows.length) {
    console.log("❌ 未找到数据");
    process.exit(1);
  }

  const db = result.rows[0].state;
  let totalJourneys = 0;
  let fixedJourneys = 0;
  const issues = [];

  for (const [uid, user] of Object.entries(db.users || {})) {
    if (!Array.isArray(user.journeys)) continue;

    for (const journey of user.journeys) {
      totalJourneys++;

      if (journey.ownerUserID && journey.ownerUserID !== uid) {
        issues.push({
          uid,
          email: user.email || user.displayName,
          journeyId: journey.id,
          journeyTitle: journey.title,
          claimedOwner: journey.ownerUserID
        });
        fixedJourneys++;
      }

      journey.ownerUserID = uid;
    }
  }

  console.log(`📊 统计:`);
  console.log(`   总journeys: ${totalJourneys}`);
  console.log(`   发现错误: ${fixedJourneys}\n`);

  if (issues.length > 0) {
    console.log("❌ 发现数据串的情况:\n");
    for (const issue of issues) {
      console.log(`用户: ${issue.email} (${issue.uid})`);
      console.log(`  错误journey: ${issue.journeyTitle} (${issue.journeyId})`);
      console.log(`  声称属于: ${issue.claimedOwner}\n`);
    }

    console.log("💾 保存修复后的数据...");
    await pool.query("UPDATE app_state SET state = $1 WHERE key = $2", [db, PG_STATE_KEY]);
    console.log("✅ 数据已修复\n");
  } else {
    console.log("✅ 数据正常，无需修复\n");
  }

  await pool.end();
}

main().catch(e => {
  console.error("❌ 错误:", e.message);
  process.exit(1);
});
