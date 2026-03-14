// 数据迁移脚本：从JSONB迁移到关系型表
// 使用方法: node migrate-data.js

const { Pool } = require("pg");
const fs = require("fs");

const DATABASE_URL = process.env.DATABASE_URL || "";
const PGHOST = process.env.PGHOST || "";
const PGPORT = Number(process.env.PGPORT || 5432);
const PGUSER = process.env.PGUSER || "";
const PGPASSWORD = process.env.PGPASSWORD || "";
const PGDATABASE = process.env.PGDATABASE || "";
const PGSSL = String(process.env.PGSSL || "").trim().toLowerCase();
const PG_STATE_KEY = process.env.PG_STATE_KEY || "global";

const poolConfig = { max: 5 };
if (DATABASE_URL) {
  poolConfig.connectionString = DATABASE_URL;
} else {
  poolConfig.host = PGHOST;
  poolConfig.port = PGPORT;
  poolConfig.user = PGUSER;
  poolConfig.password = PGPASSWORD;
  poolConfig.database = PGDATABASE;
}
if (PGSSL === "require" || PGSSL === "true" || PGSSL === "1") {
  poolConfig.ssl = { rejectUnauthorized: false };
}

const pool = new Pool(poolConfig);

async function loadOldDB() {
  const result = await pool.query("SELECT state FROM app_state WHERE key = $1", [PG_STATE_KEY]);
  if (!result.rows.length) throw new Error("No data found");
  return result.rows[0].state;
}

async function migrateUsers(db) {
  console.log("Migrating users...");
  let count = 0;
  for (const [uid, user] of Object.entries(db.users || {})) {
    await pool.query(`
      INSERT INTO users (id, email, display_name, handle, invite_code, profile_visibility,
        profile_setup_completed, handle_change_used, bio, loadout, created_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        display_name = EXCLUDED.display_name,
        handle = EXCLUDED.handle,
        profile_visibility = EXCLUDED.profile_visibility
    `, [
      uid,
      user.email || null,
      user.displayName || "Explorer",
      user.handle || null,
      user.inviteCode || null,
      user.profileVisibility || "friendsOnly",
      user.profileSetupCompleted !== false,
      user.handleChangeUsed || false,
      user.bio || "",
      JSON.stringify(user.loadout || {}),
      user.createdAt || Math.floor(Date.now() / 1000)
    ]);
    count++;
  }
  console.log(`✓ Migrated ${count} users`);
}

async function migrateAuthIdentities(db) {
  console.log("Migrating auth identities...");
  let count = 0;
  for (const [aid, identity] of Object.entries(db.authIdentities || {})) {
    await pool.query(`
      INSERT INTO auth_identities (id, user_id, provider, provider_subject, email,
        password_hash, email_verified, created_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      ON CONFLICT (id) DO NOTHING
    `, [
      aid,
      identity.userID,
      identity.provider,
      identity.providerSubject || null,
      identity.email || null,
      identity.passwordHash || null,
      identity.emailVerified || false,
      identity.createdAt || Math.floor(Date.now() / 1000),
      identity.updatedAt || Math.floor(Date.now() / 1000)
    ]);
    count++;
  }
  console.log(`✓ Migrated ${count} auth identities`);
}

async function migrateFriendships(db) {
  console.log("Migrating friendships...");
  let count = 0;
  const now = Math.floor(Date.now() / 1000);
  for (const [uid, user] of Object.entries(db.users || {})) {
    for (const fid of user.friendIDs || []) {
      await pool.query(`
        INSERT INTO friendships (user_id, friend_id, created_at)
        VALUES ($1, $2, $3)
        ON CONFLICT DO NOTHING
      `, [uid, fid, now]);
      count++;
    }
  }
  console.log(`✓ Migrated ${count} friendships`);
}

async function migrateJourneys(db) {
  console.log("Migrating journeys...");
  let count = 0;
  for (const [uid, user] of Object.entries(db.users || {})) {
    for (const journey of user.journeys || []) {
      await pool.query(`
        INSERT INTO journeys (id, user_id, title, city_id, distance, start_time, end_time,
          visibility, data, created_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        ON CONFLICT (user_id, id) DO UPDATE SET
          title = EXCLUDED.title,
          visibility = EXCLUDED.visibility,
          data = EXCLUDED.data
      `, [
        journey.id,
        uid,
        journey.title || "Journey",
        journey.cityID || null,
        journey.distance || 0,
        journey.startTime || null,
        journey.endTime || null,
        journey.visibility || "friendsOnly",
        JSON.stringify(journey),
        Math.floor(Date.now() / 1000)
      ]);
      count++;
    }
  }
  console.log(`✓ Migrated ${count} journeys`);
}

async function migrateCityCards(db) {
  console.log("Migrating city cards...");
  let count = 0;
  const now = Math.floor(Date.now() / 1000);
  for (const [uid, user] of Object.entries(db.users || {})) {
    for (const card of user.cityCards || []) {
      await pool.query(`
        INSERT INTO city_cards (user_id, city_id, city_name, country_iso2, created_at)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT DO NOTHING
      `, [uid, card.id, card.name, card.countryISO2 || null, now]);
      count++;
    }
  }
  console.log(`✓ Migrated ${count} city cards`);
}

async function migrateLikes(db) {
  console.log("Migrating likes...");
  let count = 0;
  const now = Math.floor(Date.now() / 1000);
  for (const [key, record] of Object.entries(db.likesIndex || {})) {
    for (const likerID of record.likedBy || []) {
      await pool.query(`
        INSERT INTO journey_likes (owner_user_id, journey_id, liker_user_id, created_at)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT DO NOTHING
      `, [record.ownerUserID, record.journeyID, likerID, now]);
      count++;
    }
  }
  console.log(`✓ Migrated ${count} likes`);
}

async function migrateFriendRequests(db) {
  console.log("Migrating friend requests...");
  let count = 0;
  for (const [rid, req] of Object.entries(db.friendRequestsIndex || {})) {
    await pool.query(`
      INSERT INTO friend_requests (id, from_user_id, to_user_id, note, created_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6)
      ON CONFLICT DO NOTHING
    `, [
      rid,
      req.fromUserID,
      req.toUserID,
      req.note || null,
      req.createdAt || new Date().toISOString(),
      req.updatedAt || new Date().toISOString()
    ]);
    count++;
  }
  console.log(`✓ Migrated ${count} friend requests`);
}

async function main() {
  try {
    console.log("Loading old database...");
    const db = await loadOldDB();

    console.log("\nStarting migration...");
    await migrateUsers(db);
    await migrateAuthIdentities(db);
    await migrateFriendships(db);
    await migrateJourneys(db);
    await migrateCityCards(db);
    await migrateLikes(db);
    await migrateFriendRequests(db);

    console.log("\n✓ Migration completed successfully!");
    console.log("\n⚠️  IMPORTANT: Update server.js to use new schema before restarting");
  } catch (error) {
    console.error("Migration failed:", error);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

main();
