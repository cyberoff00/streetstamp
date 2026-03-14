const fs = require("fs");

const DATA_FILE = process.env.DATA_FILE || "./data/data.json";

console.log("🔍 检查并移除跨用户的journeys...\n");

const raw = fs.readFileSync(DATA_FILE, "utf8");
const db = JSON.parse(raw);

// 第一步：建立journey ID到真实所有者的映射
const journeyOwnerMap = new Map();

for (const [uid, user] of Object.entries(db.users || {})) {
  if (!Array.isArray(user.journeys)) continue;

  for (const journey of user.journeys) {
    const jid = journey.id;
    if (!journeyOwnerMap.has(jid)) {
      journeyOwnerMap.set(jid, uid);
    }
  }
}

console.log(`📊 发现 ${journeyOwnerMap.size} 个唯一的 journey IDs\n`);

// 第二步：清理每个用户的journeys
let totalRemoved = 0;
const userIssues = [];

for (const [uid, user] of Object.entries(db.users || {})) {
  if (!Array.isArray(user.journeys)) continue;

  const originalCount = user.journeys.length;
  const validJourneys = [];
  const removedJourneys = [];

  for (const journey of user.journeys) {
    const jid = journey.id;
    const realOwner = journeyOwnerMap.get(jid);

    // 如果这个journey的ownerUserID字段存在且不匹配，说明是错误数据
    if (journey.ownerUserID && journey.ownerUserID !== uid) {
      removedJourneys.push({
        id: jid,
        title: journey.title,
        claimedOwner: journey.ownerUserID
      });
      totalRemoved++;
    } else {
      // 保留这个journey，并设置正确的ownerUserID
      journey.ownerUserID = uid;
      validJourneys.push(journey);
    }
  }

  if (removedJourneys.length > 0) {
    userIssues.push({
      uid,
      email: user.email || user.displayName,
      removed: removedJourneys,
      before: originalCount,
      after: validJourneys.length
    });
  }

  user.journeys = validJourneys;
}

// 输出报告
if (userIssues.length > 0) {
  console.log("❌ 发现数据串的用户:\n");
  for (const issue of userIssues) {
    console.log(`用户: ${issue.email} (${issue.uid})`);
    console.log(`  journeys数量: ${issue.before} → ${issue.after}`);
    console.log(`  移除的journeys:`);
    for (const j of issue.removed) {
      console.log(`    - ${j.title} (${j.id}) [声称属于: ${j.claimedOwner}]`);
    }
    console.log();
  }
}

console.log(`\n📊 总计移除 ${totalRemoved} 个错误的 journeys\n`);

if (totalRemoved > 0) {
  const backupFile = DATA_FILE + ".backup." + Date.now();
  fs.writeFileSync(backupFile, raw);
  console.log(`💾 原始数据备份: ${backupFile}`);

  fs.writeFileSync(DATA_FILE, JSON.stringify(db, null, 2));
  console.log(`✅ 清理后的数据已保存: ${DATA_FILE}\n`);
} else {
  console.log("✅ 数据正常，无需清理\n");
}
