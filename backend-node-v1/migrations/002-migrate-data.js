#!/usr/bin/env node
/**
 * Migrate data from JSON blob (app_state) into relational tables.
 *
 * Usage:
 *   DATABASE_URL=postgresql://... node migrations/002-migrate-data.js
 *
 * This script is idempotent — it uses INSERT ... ON CONFLICT DO NOTHING
 * so it can be re-run safely.
 */

const { Pool } = require("pg");
const fs = require("fs");
const path = require("path");

const DATABASE_URL = (process.env.DATABASE_URL || "").trim();
const PG_STATE_KEY = (process.env.PG_STATE_KEY || "global").trim();
const DATA_FILE = (process.env.DATA_FILE || "./data/data.json").trim();

async function loadBlob(pool) {
  // Try PostgreSQL app_state first
  if (pool) {
    const result = await pool.query(
      "SELECT state FROM app_state WHERE key = $1 LIMIT 1",
      [PG_STATE_KEY]
    );
    if (result.rows.length) {
      console.log("[migrate] loaded blob from PostgreSQL app_state");
      return result.rows[0].state;
    }
  }
  // Fall back to JSON file
  const filePath = path.resolve(DATA_FILE);
  if (fs.existsSync(filePath)) {
    const raw = fs.readFileSync(filePath, "utf8");
    console.log("[migrate] loaded blob from file:", filePath);
    return JSON.parse(raw);
  }
  throw new Error("No data source found");
}

async function migrate() {
  const pool = DATABASE_URL
    ? new Pool({ connectionString: DATABASE_URL })
    : null;

  if (!pool) {
    console.error("DATABASE_URL is required");
    process.exit(1);
  }

  // Run schema first
  const schemaSQL = fs.readFileSync(
    path.join(__dirname, "001-create-tables.sql"),
    "utf8"
  );
  await pool.query(schemaSQL);
  console.log("[migrate] schema created/verified");

  const db = await loadBlob(pool);
  const stats = {};
  const count = (key) => { stats[key] = (stats[key] || 0) + 1; };

  // ---- 1. users ----
  for (const [uid, user] of Object.entries(db.users || {})) {
    await pool.query(
      `INSERT INTO users (id, email, display_name, handle, invite_code,
        profile_visibility, profile_setup_completed, handle_change_used,
        bio, loadout, provider, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
       ON CONFLICT (id) DO NOTHING`,
      [
        uid,
        user.email || null,
        user.displayName || "Explorer",
        user.handle || null,
        user.inviteCode || null,
        user.profileVisibility || "friendsOnly",
        user.profileSetupCompleted ?? false,
        user.handleChangeUsed ?? false,
        user.bio || "",
        user.loadout ? JSON.stringify(user.loadout) : null,
        user.provider || null,
        user.createdAt || 0,
      ]
    );
    count("users");

    // ---- friendships ----
    for (const friendID of user.friendIDs || []) {
      if (!friendID || !db.users[friendID]) continue;
      await pool.query(
        `INSERT INTO friendships (user_id, friend_id, created_at)
         VALUES ($1, $2, $3)
         ON CONFLICT DO NOTHING`,
        [uid, friendID, user.createdAt || 0]
      );
      count("friendships");
    }

    // ---- journeys (nested in user) ----
    for (const journey of user.journeys || []) {
      if (!journey || !journey.id) continue;
      await pool.query(
        `INSERT INTO journeys (id, user_id, title, city_id, distance,
          start_time, end_time, visibility, data, created_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
         ON CONFLICT DO NOTHING`,
        [
          journey.id,
          uid,
          journey.title || null,
          journey.cityID || journey.cityId || null,
          journey.distance || 0,
          journey.startTime ? new Date(journey.startTime).toISOString() : null,
          journey.endTime ? new Date(journey.endTime).toISOString() : null,
          journey.visibility || "friendsOnly",
          JSON.stringify(journey),
          journey.createdAt || user.createdAt || 0,
        ]
      );
      count("journeys");
    }

    // ---- city_cards (nested in user) ----
    for (const card of user.cityCards || []) {
      if (!card || !card.cityID) continue;
      await pool.query(
        `INSERT INTO city_cards (user_id, city_id, city_name, country_iso2, created_at)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT DO NOTHING`,
        [
          uid,
          card.cityID,
          card.cityName || card.cityID,
          card.countryISO2 || null,
          card.createdAt || user.createdAt || 0,
        ]
      );
      count("city_cards");
    }

    // ---- notifications (nested in user) ----
    for (const n of user.notifications || []) {
      if (!n || !n.id) continue;
      await pool.query(
        `INSERT INTO notifications (id, user_id, type, from_user_id,
          from_display_name, journey_id, journey_title, message, read, created_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
         ON CONFLICT DO NOTHING`,
        [
          n.id,
          uid,
          n.type || "unknown",
          n.fromUserID || null,
          n.fromDisplayName || null,
          n.journeyID || null,
          n.journeyTitle || null,
          n.message || "",
          n.read ?? false,
          n.createdAt ? new Date(n.createdAt).toISOString() : new Date().toISOString(),
        ]
      );
      count("notifications");
    }

    // ---- postcard_reactions (nested in user.postcardReactions) ----
    for (const [messageID, r] of Object.entries(user.postcardReactions || {})) {
      if (!r) continue;
      await pool.query(
        `INSERT INTO postcard_reactions (id, postcard_message_id, from_user_id,
          viewed_at, reaction_emoji, comment, reacted_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7)
         ON CONFLICT DO NOTHING`,
        [
          r.id || `pr_migrated_${uid}_${messageID}`,
          messageID,
          r.fromUserID || uid,
          r.viewedAt ? new Date(r.viewedAt).toISOString() : null,
          r.reactionEmoji || null,
          r.comment || null,
          r.reactedAt ? new Date(r.reactedAt).toISOString() : null,
        ]
      );
      count("postcard_reactions");
    }
  }

  // ---- 2. auth_identities ----
  for (const [aid, identity] of Object.entries(db.authIdentities || {})) {
    if (!identity || !identity.userID) continue;
    await pool.query(
      `INSERT INTO auth_identities (id, user_id, provider, provider_subject,
        email, password_hash, email_verified, created_at, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
       ON CONFLICT (id) DO NOTHING`,
      [
        aid,
        identity.userID,
        identity.provider || "unknown",
        identity.providerSubject || null,
        identity.email || null,
        identity.passwordHash || null,
        identity.emailVerified ?? false,
        identity.createdAt || 0,
        identity.updatedAt || identity.createdAt || 0,
      ]
    );
    count("auth_identities");
  }

  // ---- 3. oauth_index ----
  for (const [key, userID] of Object.entries(db.oauthIndex || {})) {
    if (!key || !userID) continue;
    await pool.query(
      `INSERT INTO oauth_index (oauth_key, user_id) VALUES ($1, $2)
       ON CONFLICT DO NOTHING`,
      [key, userID]
    );
    count("oauth_index");
  }

  // ---- 4. firebase_identities ----
  for (const [fbUID, record] of Object.entries(db.firebaseIdentityIndex || {})) {
    if (!record || !record.appUserId) continue;
    await pool.query(
      `INSERT INTO firebase_identities (firebase_uid, app_user_id, email,
        email_verified, providers, created_at, last_login_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT DO NOTHING`,
      [
        fbUID,
        record.appUserId,
        record.email || null,
        record.emailVerified ?? false,
        record.providers ? JSON.stringify(record.providers) : null,
        record.createdAt || 0,
        record.lastLoginAt || 0,
      ]
    );
    count("firebase_identities");
  }

  // ---- 5. email_verification_tokens ----
  for (const [tid, token] of Object.entries(db.emailVerificationTokens || {})) {
    if (!token || !token.userID) continue;
    await pool.query(
      `INSERT INTO email_verification_tokens (id, user_id, email, token_hash,
        expires_at, used_at, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT DO NOTHING`,
      [
        tid,
        token.userID,
        token.email || "",
        token.tokenHash || "",
        token.expiresAt || 0,
        token.usedAt || null,
        token.createdAt || 0,
      ]
    );
    count("email_verification_tokens");
  }

  // ---- 6. password_reset_tokens ----
  for (const [tid, token] of Object.entries(db.passwordResetTokens || {})) {
    if (!token || !token.userID) continue;
    await pool.query(
      `INSERT INTO password_reset_tokens (id, user_id, email, token_hash,
        expires_at, used_at, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT DO NOTHING`,
      [
        tid,
        token.userID,
        token.email || "",
        token.tokenHash || "",
        token.expiresAt || 0,
        token.usedAt || null,
        token.createdAt || 0,
      ]
    );
    count("password_reset_tokens");
  }

  // ---- 7. refresh_tokens ----
  for (const [tid, token] of Object.entries(db.refreshTokens || {})) {
    if (!token || !token.userID) continue;
    await pool.query(
      `INSERT INTO refresh_tokens (id, user_id, token_hash, device_info,
        expires_at, revoked_at, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT DO NOTHING`,
      [
        tid,
        token.userID,
        token.tokenHash || "",
        token.deviceInfo || null,
        token.expiresAt || 0,
        token.revokedAt || null,
        token.createdAt || 0,
      ]
    );
    count("refresh_tokens");
  }

  // ---- 8. friend_requests ----
  for (const [rid, req] of Object.entries(db.friendRequestsIndex || {})) {
    if (!req || !req.fromUserID || !req.toUserID) continue;
    await pool.query(
      `INSERT INTO friend_requests (id, from_user_id, to_user_id, note,
        created_at, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6)
       ON CONFLICT DO NOTHING`,
      [
        rid,
        req.fromUserID,
        req.toUserID,
        req.note || null,
        req.createdAt ? new Date(req.createdAt).toISOString() : new Date().toISOString(),
        req.updatedAt ? new Date(req.updatedAt).toISOString() : new Date().toISOString(),
      ]
    );
    count("friend_requests");
  }

  // ---- 9. likes ----
  for (const [, record] of Object.entries(db.likesIndex || {})) {
    if (!record || !record.ownerUserID || !record.journeyID) continue;
    for (const likerID of record.likerIDs || []) {
      if (!likerID) continue;
      const likedAt = record.likedAtByUserID?.[likerID];
      await pool.query(
        `INSERT INTO journey_likes (owner_user_id, journey_id, liker_user_id, created_at)
         VALUES ($1,$2,$3,$4)
         ON CONFLICT DO NOTHING`,
        [
          record.ownerUserID,
          record.journeyID,
          likerID,
          likedAt ? new Date(likedAt).toISOString() : new Date().toISOString(),
        ]
      );
      count("journey_likes");
    }
  }

  // ---- 10. postcards ----
  for (const [, pc] of Object.entries(db.postcardsIndex || {})) {
    if (!pc || !pc.messageID) continue;
    await pool.query(
      `INSERT INTO postcards (message_id, from_user_id, from_display_name,
        to_user_id, to_display_name, city_id, city_name, photo_url,
        message_text, client_draft_id, status, sent_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
       ON CONFLICT DO NOTHING`,
      [
        pc.messageID,
        pc.fromUserID,
        pc.fromDisplayName || null,
        pc.toUserID,
        pc.toDisplayName || null,
        pc.cityID || "",
        pc.cityName || "",
        pc.photoURL || null,
        pc.messageText || "",
        pc.clientDraftID || null,
        pc.status || "sent",
        pc.sentAt ? new Date(pc.sentAt).toISOString() : new Date().toISOString(),
      ]
    );
    count("postcards");
  }

  console.log("\n[migrate] Migration complete. Row counts:");
  for (const [table, n] of Object.entries(stats).sort()) {
    console.log(`  ${table}: ${n}`);
  }

  // Verify
  const tables = [
    "users", "auth_identities", "oauth_index", "firebase_identities",
    "email_verification_tokens", "password_reset_tokens", "refresh_tokens",
    "friendships", "friend_requests", "journeys", "city_cards",
    "journey_likes", "notifications", "postcards", "postcard_reactions",
  ];
  console.log("\n[migrate] Verification (actual row counts in DB):");
  for (const t of tables) {
    const r = await pool.query(`SELECT COUNT(*) AS c FROM ${t}`);
    console.log(`  ${t}: ${r.rows[0].c}`);
  }

  await pool.end();
  console.log("\n[migrate] Done.");
}

migrate().catch((e) => {
  console.error("[migrate] FATAL:", e);
  process.exit(1);
});
