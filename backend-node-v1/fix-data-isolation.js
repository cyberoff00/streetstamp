const fs = require("fs");

const DATA_FILE = process.env.DATA_FILE || "./data/data.json";

console.log("🔍 检查数据隔离问题...");

const raw = fs.readFileSync(DATA_FILE, "utf8");
const db = JSON.parse(raw);

let totalJourneys = 0;
let fixedJourneys = 0;

for (const [uid, user] of Object.entries(db.users || {})) {
  if (!Array.isArray(user.journeys)) continue;

  for (const journey of user.journeys) {
    totalJourneys++;

    // 如果journey已经有ownerUserID且不匹配当前用户，说明数据串了
    if (journey.ownerUserID && journey.ownerUserID !== uid) {
      console.log(`❌ 发现错误: 用户 ${uid} (${user.email || user.displayName}) 的 journey ${journey.id} 属于 ${journey.ownerUserID}`);
      fixedJourneys++;
    }

    // 强制设置正确的ownerUserID
    journey.ownerUserID = uid;
  }
}

console.log(`\n📊 统计:`);
console.log(`   总journeys: ${totalJourneys}`);
console.log(`   修复的journeys: ${fixedJourneys}`);

if (fixedJourneys > 0) {
  const backupFile = DATA_FILE + ".backup." + Date.now();
  fs.writeFileSync(backupFile, raw);
  console.log(`\n💾 备份已保存: ${backupFile}`);

  fs.writeFileSync(DATA_FILE, JSON.stringify(db, null, 2));
  console.log(`✅ 数据已修复并保存到: ${DATA_FILE}`);
} else {
  console.log(`\n✅ 数据正常，无需修复`);
}
