/**
 * db-relational.js — Relational PostgreSQL data access layer.
 *
 * Replaces the in-memory `db` object + JSON blob persistence with
 * direct SQL queries against normalized tables.
 *
 * Each function maps 1:1 to an operation that server.js currently does
 * against `db.users[uid]`, `db.emailIndex[email]`, etc.
 *
 * All functions accept `pool` (pg.Pool) as first argument.
 */

// ============================================================
// Users
// ============================================================

async function getUserByID(pool, uid) {
  const { rows } = await pool.query("SELECT * FROM users WHERE id = $1", [uid]);
  return rows[0] ? userRowToObj(rows[0]) : null;
}

async function getUsersByIDs(pool, uids) {
  if (!uids.length) return {};
  const { rows } = await pool.query(
    "SELECT * FROM users WHERE id = ANY($1::text[])",
    [uids]
  );
  const map = {};
  for (const row of rows) map[row.id] = userRowToObj(row);
  return map;
}

async function getUserByEmail(pool, email) {
  if (!email) return null;
  const { rows } = await pool.query("SELECT * FROM users WHERE email = $1", [email]);
  return rows[0] ? userRowToObj(rows[0]) : null;
}

async function getUserByHandle(pool, handle) {
  if (!handle) return null;
  const { rows } = await pool.query("SELECT * FROM users WHERE handle = $1", [handle]);
  return rows[0] ? userRowToObj(rows[0]) : null;
}

async function getUserByInviteCode(pool, code) {
  if (!code) return null;
  const { rows } = await pool.query("SELECT * FROM users WHERE invite_code = $1", [code]);
  return rows[0] ? userRowToObj(rows[0]) : null;
}

async function insertUser(pool, user) {
  await pool.query(
    `INSERT INTO users (id, email, display_name, handle, invite_code,
      profile_visibility, profile_setup_completed, handle_change_used,
      bio, loadout, provider, created_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
    [
      user.id,
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
      user.createdAt || Math.floor(Date.now() / 1000),
    ]
  );
}

async function updateUser(pool, uid, fields) {
  const setClauses = [];
  const values = [];
  let idx = 1;

  const columnMap = {
    email: "email",
    displayName: "display_name",
    handle: "handle",
    inviteCode: "invite_code",
    profileVisibility: "profile_visibility",
    profileSetupCompleted: "profile_setup_completed",
    handleChangeUsed: "handle_change_used",
    bio: "bio",
    loadout: "loadout",
    provider: "provider",
  };

  for (const [key, col] of Object.entries(columnMap)) {
    if (key in fields) {
      let val = fields[key];
      if (key === "loadout" && val && typeof val === "object") val = JSON.stringify(val);
      setClauses.push(`${col} = $${idx}`);
      values.push(val);
      idx++;
    }
  }

  if (!setClauses.length) return;
  values.push(uid);
  await pool.query(
    `UPDATE users SET ${setClauses.join(", ")} WHERE id = $${idx}`,
    values
  );
}

async function deleteUser(pool, uid) {
  await pool.query("DELETE FROM users WHERE id = $1", [uid]);
}

async function handleExists(pool, handle, excludeUID) {
  const { rows } = await pool.query(
    "SELECT id FROM users WHERE handle = $1 AND id != $2",
    [handle, excludeUID || ""]
  );
  return rows.length > 0;
}

async function displayNameExists(pool, displayName, excludeUID) {
  const { rows } = await pool.query(
    "SELECT id FROM users WHERE display_name = $1 AND id != $2",
    [displayName, excludeUID || ""]
  );
  return rows.length > 0;
}

async function getAllUsersOrdered(pool) {
  const { rows } = await pool.query(
    "SELECT * FROM users ORDER BY created_at ASC, id ASC"
  );
  return rows.map(userRowToObj);
}

function userRowToObj(row) {
  return {
    id: row.id,
    email: row.email,
    displayName: row.display_name,
    handle: row.handle,
    inviteCode: row.invite_code,
    profileVisibility: row.profile_visibility,
    profileSetupCompleted: row.profile_setup_completed,
    handleChangeUsed: row.handle_change_used,
    bio: row.bio,
    loadout: row.loadout || null,
    provider: row.provider,
    createdAt: Number(row.created_at),
  };
}

// ============================================================
// Auth Identities
// ============================================================

async function getAuthIdentityByID(pool, id) {
  const { rows } = await pool.query("SELECT * FROM auth_identities WHERE id = $1", [id]);
  return rows[0] ? authIdentityRowToObj(rows[0]) : null;
}

async function findAuthIdentityByProviderSubject(pool, provider, subject) {
  if (!provider || !subject) return null;
  const { rows } = await pool.query(
    "SELECT * FROM auth_identities WHERE provider = $1 AND provider_subject = $2 LIMIT 1",
    [provider, subject]
  );
  return rows[0] ? authIdentityRowToObj(rows[0]) : null;
}

async function findEmailPasswordIdentity(pool, email) {
  if (!email) return null;
  const { rows } = await pool.query(
    "SELECT * FROM auth_identities WHERE provider = 'email_password' AND email = $1 LIMIT 1",
    [email]
  );
  return rows[0] ? authIdentityRowToObj(rows[0]) : null;
}

async function findVerifiedEmailPasswordIdentity(pool, email) {
  if (!email) return null;
  const { rows } = await pool.query(
    "SELECT * FROM auth_identities WHERE provider = 'email_password' AND email = $1 AND email_verified = true LIMIT 1",
    [email]
  );
  return rows[0] ? authIdentityRowToObj(rows[0]) : null;
}

async function findAuthIdentitiesByUserID(pool, uid) {
  const { rows } = await pool.query(
    "SELECT * FROM auth_identities WHERE user_id = $1",
    [uid]
  );
  return rows.map(authIdentityRowToObj);
}

async function insertAuthIdentity(pool, identity) {
  await pool.query(
    `INSERT INTO auth_identities (id, user_id, provider, provider_subject,
      email, password_hash, email_verified, created_at, updated_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
    [
      identity.id,
      identity.userID,
      identity.provider,
      identity.providerSubject || null,
      identity.email || null,
      identity.passwordHash || null,
      identity.emailVerified ?? false,
      identity.createdAt,
      identity.updatedAt,
    ]
  );
}

async function updateAuthIdentity(pool, id, fields) {
  const setClauses = [];
  const values = [];
  let idx = 1;

  const columnMap = {
    userID: "user_id",
    email: "email",
    passwordHash: "password_hash",
    emailVerified: "email_verified",
    updatedAt: "updated_at",
  };

  for (const [key, col] of Object.entries(columnMap)) {
    if (key in fields) {
      setClauses.push(`${col} = $${idx}`);
      values.push(fields[key]);
      idx++;
    }
  }

  if (!setClauses.length) return;
  values.push(id);
  await pool.query(
    `UPDATE auth_identities SET ${setClauses.join(", ")} WHERE id = $${idx}`,
    values
  );
}

function authIdentityRowToObj(row) {
  return {
    id: row.id,
    userID: row.user_id,
    provider: row.provider,
    providerSubject: row.provider_subject,
    email: row.email,
    passwordHash: row.password_hash,
    emailVerified: row.email_verified,
    createdAt: Number(row.created_at),
    updatedAt: Number(row.updated_at),
  };
}

// ============================================================
// OAuth Index
// ============================================================

async function getOAuthUser(pool, oauthKey) {
  const { rows } = await pool.query(
    "SELECT user_id FROM oauth_index WHERE oauth_key = $1",
    [oauthKey]
  );
  return rows[0]?.user_id || null;
}

async function setOAuthUser(pool, oauthKey, userID) {
  await pool.query(
    `INSERT INTO oauth_index (oauth_key, user_id) VALUES ($1, $2)
     ON CONFLICT (oauth_key) DO UPDATE SET user_id = EXCLUDED.user_id`,
    [oauthKey, userID]
  );
}

async function transferOAuthEntries(pool, fromUID, toUID) {
  await pool.query(
    "UPDATE oauth_index SET user_id = $1 WHERE user_id = $2",
    [toUID, fromUID]
  );
}

// ============================================================
// Firebase Identities
// ============================================================

async function getFirebaseIdentity(pool, firebaseUID) {
  const { rows } = await pool.query(
    "SELECT * FROM firebase_identities WHERE firebase_uid = $1",
    [firebaseUID]
  );
  if (!rows[0]) return null;
  const r = rows[0];
  return {
    firebaseUid: r.firebase_uid,
    appUserId: r.app_user_id,
    email: r.email,
    emailVerified: r.email_verified,
    providers: r.providers || [],
    createdAt: r.created_at,
    lastLoginAt: r.last_login_at,
  };
}

async function upsertFirebaseIdentity(pool, record) {
  await pool.query(
    `INSERT INTO firebase_identities (firebase_uid, app_user_id, email,
      email_verified, providers, created_at, last_login_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7)
     ON CONFLICT (firebase_uid) DO UPDATE SET
       app_user_id = EXCLUDED.app_user_id,
       email = EXCLUDED.email,
       email_verified = EXCLUDED.email_verified,
       providers = EXCLUDED.providers,
       last_login_at = EXCLUDED.last_login_at`,
    [
      record.firebaseUid,
      record.appUserId,
      record.email || null,
      record.emailVerified ?? false,
      JSON.stringify(record.providers || []),
      record.createdAt,
      record.lastLoginAt,
    ]
  );
}

// ============================================================
// Email Verification Tokens
// ============================================================

async function insertEmailVerificationToken(pool, token) {
  await pool.query(
    `INSERT INTO email_verification_tokens (id, user_id, email, token_hash,
      expires_at, used_at, created_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7)`,
    [token.id, token.userID, token.email, token.tokenHash, token.expiresAt, token.usedAt, token.createdAt]
  );
}

async function findEmailVerificationByHash(pool, tokenHash) {
  const { rows } = await pool.query(
    "SELECT * FROM email_verification_tokens WHERE token_hash = $1 LIMIT 1",
    [tokenHash]
  );
  if (!rows[0]) return null;
  const r = rows[0];
  return {
    id: r.id, userID: r.user_id, email: r.email,
    tokenHash: r.token_hash, expiresAt: Number(r.expires_at),
    usedAt: r.used_at ? Number(r.used_at) : null, createdAt: Number(r.created_at),
  };
}

async function markEmailVerificationUsed(pool, id, usedAt) {
  await pool.query(
    "UPDATE email_verification_tokens SET used_at = $1 WHERE id = $2",
    [usedAt, id]
  );
}

// ============================================================
// Password Reset Tokens
// ============================================================

async function insertPasswordResetToken(pool, token) {
  await pool.query(
    `INSERT INTO password_reset_tokens (id, user_id, email, token_hash,
      expires_at, used_at, created_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7)`,
    [token.id, token.userID, token.email, token.tokenHash, token.expiresAt, token.usedAt, token.createdAt]
  );
}

async function findPasswordResetByHash(pool, tokenHash) {
  const { rows } = await pool.query(
    "SELECT * FROM password_reset_tokens WHERE token_hash = $1 LIMIT 1",
    [tokenHash]
  );
  if (!rows[0]) return null;
  const r = rows[0];
  return {
    id: r.id, userID: r.user_id, email: r.email,
    tokenHash: r.token_hash, expiresAt: Number(r.expires_at),
    usedAt: r.used_at ? Number(r.used_at) : null, createdAt: Number(r.created_at),
  };
}

async function markPasswordResetUsed(pool, id, usedAt) {
  await pool.query(
    "UPDATE password_reset_tokens SET used_at = $1 WHERE id = $2",
    [usedAt, id]
  );
}

// ============================================================
// Refresh Tokens
// ============================================================

async function insertRefreshToken(pool, token) {
  await pool.query(
    `INSERT INTO refresh_tokens (id, user_id, token_hash, device_info,
      expires_at, revoked_at, created_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7)`,
    [token.id, token.userID, token.tokenHash, token.deviceInfo, token.expiresAt, token.revokedAt, token.createdAt]
  );
}

async function findRefreshTokenByHash(pool, tokenHash) {
  const { rows } = await pool.query(
    "SELECT * FROM refresh_tokens WHERE token_hash = $1 LIMIT 1",
    [tokenHash]
  );
  if (!rows[0]) return null;
  const r = rows[0];
  return {
    id: r.id, userID: r.user_id, tokenHash: r.token_hash,
    deviceInfo: r.device_info, expiresAt: Number(r.expires_at),
    revokedAt: r.revoked_at ? Number(r.revoked_at) : null, createdAt: Number(r.created_at),
  };
}

async function revokeRefreshTokensForUser(pool, userID) {
  const revokedAt = Math.floor(Date.now() / 1000);
  await pool.query(
    "UPDATE refresh_tokens SET revoked_at = $1 WHERE user_id = $2 AND revoked_at IS NULL",
    [revokedAt, userID]
  );
}

async function revokeRefreshToken(pool, id) {
  await pool.query(
    "UPDATE refresh_tokens SET revoked_at = $1 WHERE id = $2",
    [Math.floor(Date.now() / 1000), id]
  );
}

// ============================================================
// Friendships
// ============================================================

async function getFriendIDs(pool, uid) {
  const { rows } = await pool.query(
    "SELECT friend_id FROM friendships WHERE user_id = $1",
    [uid]
  );
  return rows.map((r) => r.friend_id);
}

async function areFriends(pool, uid1, uid2) {
  const { rows } = await pool.query(
    "SELECT 1 FROM friendships WHERE user_id = $1 AND friend_id = $2",
    [uid1, uid2]
  );
  return rows.length > 0;
}

async function addFriendship(pool, uid1, uid2) {
  const now = Math.floor(Date.now() / 1000);
  await pool.query(
    `INSERT INTO friendships (user_id, friend_id, created_at) VALUES ($1, $2, $3)
     ON CONFLICT DO NOTHING`,
    [uid1, uid2, now]
  );
  await pool.query(
    `INSERT INTO friendships (user_id, friend_id, created_at) VALUES ($1, $2, $3)
     ON CONFLICT DO NOTHING`,
    [uid2, uid1, now]
  );
}

async function removeFriendship(pool, uid1, uid2) {
  await pool.query(
    "DELETE FROM friendships WHERE (user_id = $1 AND friend_id = $2) OR (user_id = $2 AND friend_id = $1)",
    [uid1, uid2]
  );
}

// ============================================================
// Friend Requests
// ============================================================

async function getFriendRequest(pool, id) {
  const { rows } = await pool.query("SELECT * FROM friend_requests WHERE id = $1", [id]);
  if (!rows[0]) return null;
  return friendRequestRowToObj(rows[0]);
}

async function getFriendRequestsTo(pool, uid) {
  const { rows } = await pool.query(
    "SELECT * FROM friend_requests WHERE to_user_id = $1 ORDER BY created_at DESC",
    [uid]
  );
  return rows.map(friendRequestRowToObj);
}

async function getFriendRequestsFrom(pool, uid) {
  const { rows } = await pool.query(
    "SELECT * FROM friend_requests WHERE from_user_id = $1 ORDER BY created_at DESC",
    [uid]
  );
  return rows.map(friendRequestRowToObj);
}

async function findPendingFriendRequest(pool, fromUID, toUID) {
  const { rows } = await pool.query(
    "SELECT * FROM friend_requests WHERE from_user_id = $1 AND to_user_id = $2 LIMIT 1",
    [fromUID, toUID]
  );
  return rows[0] ? friendRequestRowToObj(rows[0]) : null;
}

async function insertFriendRequest(pool, req) {
  await pool.query(
    `INSERT INTO friend_requests (id, from_user_id, to_user_id, note, created_at, updated_at)
     VALUES ($1,$2,$3,$4,$5,$6)`,
    [req.id, req.fromUserID, req.toUserID, req.note || null, req.createdAt, req.updatedAt]
  );
}

async function deleteFriendRequest(pool, id) {
  await pool.query("DELETE FROM friend_requests WHERE id = $1", [id]);
}

function friendRequestRowToObj(row) {
  return {
    id: row.id,
    fromUserID: row.from_user_id,
    toUserID: row.to_user_id,
    note: row.note,
    createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : String(row.created_at),
    updatedAt: row.updated_at instanceof Date ? row.updated_at.toISOString() : String(row.updated_at),
  };
}

// ============================================================
// Journeys
// ============================================================

async function getJourneysByUser(pool, uid) {
  const { rows } = await pool.query(
    "SELECT data FROM journeys WHERE user_id = $1 ORDER BY end_time DESC NULLS LAST",
    [uid]
  );
  return rows.map((r) => r.data);
}

async function getJourney(pool, uid, journeyID) {
  const { rows } = await pool.query(
    "SELECT data FROM journeys WHERE user_id = $1 AND id = $2",
    [uid, journeyID]
  );
  return rows[0]?.data || null;
}

async function upsertJourney(pool, uid, journey) {
  await pool.query(
    `INSERT INTO journeys (id, user_id, title, city_id, distance,
      start_time, end_time, visibility, data, created_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
     ON CONFLICT (user_id, id) DO UPDATE SET
       title = EXCLUDED.title,
       city_id = EXCLUDED.city_id,
       distance = EXCLUDED.distance,
       start_time = EXCLUDED.start_time,
       end_time = EXCLUDED.end_time,
       visibility = EXCLUDED.visibility,
       data = EXCLUDED.data`,
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
      journey.createdAt || Math.floor(Date.now() / 1000),
    ]
  );
}

async function deleteJourneys(pool, uid, journeyIDs) {
  if (!journeyIDs.length) return;
  await pool.query(
    "DELETE FROM journeys WHERE user_id = $1 AND id = ANY($2::text[])",
    [uid, journeyIDs]
  );
}

async function deleteAllJourneys(pool, uid) {
  await pool.query("DELETE FROM journeys WHERE user_id = $1", [uid]);
}

// ============================================================
// City Cards
// ============================================================

async function getCityCardsByUser(pool, uid) {
  const { rows } = await pool.query(
    "SELECT * FROM city_cards WHERE user_id = $1",
    [uid]
  );
  return rows.map((r) => ({
    id: r.city_id,
    name: r.city_name,
    countryISO2: r.country_iso2,
  }));
}

async function upsertCityCard(pool, uid, card) {
  await pool.query(
    `INSERT INTO city_cards (user_id, city_id, city_name, country_iso2, created_at)
     VALUES ($1,$2,$3,$4,$5)
     ON CONFLICT (user_id, city_id) DO UPDATE SET
       city_name = EXCLUDED.city_name,
       country_iso2 = EXCLUDED.country_iso2`,
    [uid, card.id, card.name || card.id, card.countryISO2 || null, Math.floor(Date.now() / 1000)]
  );
}

async function replaceCityCards(pool, uid, cards) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("DELETE FROM city_cards WHERE user_id = $1", [uid]);
    for (const card of cards) {
      await client.query(
        `INSERT INTO city_cards (user_id, city_id, city_name, country_iso2, created_at)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT DO NOTHING`,
        [uid, card.id, card.name || card.id, card.countryISO2 || null, Math.floor(Date.now() / 1000)]
      );
    }
    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}

// ============================================================
// Journey Likes
// ============================================================

async function getJourneyLikers(pool, ownerUID, journeyID) {
  const { rows } = await pool.query(
    "SELECT liker_user_id, created_at FROM journey_likes WHERE owner_user_id = $1 AND journey_id = $2",
    [ownerUID, journeyID]
  );
  return rows.map((r) => ({
    likerUserID: r.liker_user_id,
    createdAt: r.created_at instanceof Date ? r.created_at.toISOString() : String(r.created_at),
  }));
}

async function addJourneyLike(pool, ownerUID, journeyID, likerUID) {
  await pool.query(
    `INSERT INTO journey_likes (owner_user_id, journey_id, liker_user_id, created_at)
     VALUES ($1,$2,$3,NOW())
     ON CONFLICT DO NOTHING`,
    [ownerUID, journeyID, likerUID]
  );
}

async function removeJourneyLike(pool, ownerUID, journeyID, likerUID) {
  await pool.query(
    "DELETE FROM journey_likes WHERE owner_user_id = $1 AND journey_id = $2 AND liker_user_id = $3",
    [ownerUID, journeyID, likerUID]
  );
}

async function getJourneyLikeCount(pool, ownerUID, journeyID) {
  const { rows } = await pool.query(
    "SELECT COUNT(*) AS c FROM journey_likes WHERE owner_user_id = $1 AND journey_id = $2",
    [ownerUID, journeyID]
  );
  return Number(rows[0].c);
}

async function hasUserLikedJourney(pool, ownerUID, journeyID, likerUID) {
  const { rows } = await pool.query(
    "SELECT 1 FROM journey_likes WHERE owner_user_id = $1 AND journey_id = $2 AND liker_user_id = $3",
    [ownerUID, journeyID, likerUID]
  );
  return rows.length > 0;
}

async function batchGetJourneyLikes(pool, keys) {
  // keys: [{ownerUserID, journeyID}]
  if (!keys.length) return {};
  const result = {};
  for (const k of keys) {
    const likers = await getJourneyLikers(pool, k.ownerUserID, k.journeyID);
    result[`${k.ownerUserID}:${k.journeyID}`] = {
      ownerUserID: k.ownerUserID,
      journeyID: k.journeyID,
      likerIDs: likers.map((l) => l.likerUserID),
      likedAtByUserID: Object.fromEntries(likers.map((l) => [l.likerUserID, l.createdAt])),
    };
  }
  return result;
}

// ============================================================
// Notifications
// ============================================================

async function getNotifications(pool, uid, limit = 400) {
  const { rows } = await pool.query(
    "SELECT * FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2",
    [uid, limit]
  );
  return rows.map(notificationRowToObj);
}

async function insertNotification(pool, n) {
  await pool.query(
    `INSERT INTO notifications (id, user_id, type, from_user_id, from_display_name,
      journey_id, journey_title, message, read, created_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
    [
      n.id, n.userID, n.type, n.fromUserID || null,
      n.fromDisplayName || null, n.journeyID || null,
      n.journeyTitle || null, n.message,
      n.read ?? false, n.createdAt,
    ]
  );
  // Enforce cap
  await pool.query(
    `DELETE FROM notifications WHERE user_id = $1 AND id NOT IN (
       SELECT id FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT 400
     )`,
    [n.userID]
  );
}

async function markNotificationsRead(pool, uid, ids) {
  if (!ids.length) return;
  await pool.query(
    "UPDATE notifications SET read = true WHERE user_id = $1 AND id = ANY($2::text[])",
    [uid, ids]
  );
}

async function markAllNotificationsRead(pool, uid) {
  await pool.query(
    "UPDATE notifications SET read = true WHERE user_id = $1 AND read = false",
    [uid]
  );
}

function notificationRowToObj(row) {
  return {
    id: row.id,
    type: row.type,
    fromUserID: row.from_user_id,
    fromDisplayName: row.from_display_name,
    journeyID: row.journey_id,
    journeyTitle: row.journey_title,
    message: row.message,
    read: row.read,
    createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : String(row.created_at),
  };
}

// ============================================================
// Postcards
// ============================================================

async function getPostcardByID(pool, messageID) {
  const { rows } = await pool.query("SELECT * FROM postcards WHERE message_id = $1", [messageID]);
  return rows[0] ? postcardRowToObj(rows[0]) : null;
}

async function getPostcardsForUser(pool, uid, box) {
  const col = box === "received" ? "to_user_id" : "from_user_id";
  const { rows } = await pool.query(
    `SELECT * FROM postcards WHERE ${col} = $1 ORDER BY sent_at DESC`,
    [uid]
  );
  return rows.map(postcardRowToObj);
}

async function insertPostcard(pool, pc) {
  await pool.query(
    `INSERT INTO postcards (message_id, from_user_id, from_display_name,
      to_user_id, to_display_name, city_id, city_name, photo_url,
      message_text, client_draft_id, status, sent_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
     ON CONFLICT (message_id) DO NOTHING`,
    [
      pc.messageID, pc.fromUserID, pc.fromDisplayName || null,
      pc.toUserID, pc.toDisplayName || null,
      pc.cityID || "", pc.cityName || "",
      pc.photoURL || null, pc.messageText || "",
      pc.clientDraftID || null, pc.status || "sent",
      pc.sentAt || new Date().toISOString(),
    ]
  );
}

async function findPostcardByDraft(pool, fromUID, clientDraftID) {
  if (!clientDraftID) return null;
  const { rows } = await pool.query(
    "SELECT * FROM postcards WHERE from_user_id = $1 AND client_draft_id = $2 LIMIT 1",
    [fromUID, clientDraftID]
  );
  return rows[0] ? postcardRowToObj(rows[0]) : null;
}

function postcardRowToObj(row) {
  return {
    messageID: row.message_id,
    type: "postcard",
    fromUserID: row.from_user_id,
    fromDisplayName: row.from_display_name,
    toUserID: row.to_user_id,
    toDisplayName: row.to_display_name,
    cityID: row.city_id,
    cityName: row.city_name,
    photoURL: row.photo_url,
    messageText: row.message_text,
    clientDraftID: row.client_draft_id,
    status: row.status,
    sentAt: row.sent_at instanceof Date ? row.sent_at.toISOString() : String(row.sent_at),
  };
}

// ============================================================
// Postcard Reactions
// ============================================================

async function getPostcardReaction(pool, messageID, fromUID) {
  const { rows } = await pool.query(
    "SELECT * FROM postcard_reactions WHERE postcard_message_id = $1 AND from_user_id = $2",
    [messageID, fromUID]
  );
  if (!rows[0]) return null;
  const r = rows[0];
  return {
    id: r.id,
    postcardMessageID: r.postcard_message_id,
    fromUserID: r.from_user_id,
    viewedAt: r.viewed_at instanceof Date ? r.viewed_at.toISOString() : r.viewed_at,
    reactionEmoji: r.reaction_emoji,
    comment: r.comment,
    reactedAt: r.reacted_at instanceof Date ? r.reacted_at.toISOString() : r.reacted_at,
  };
}

async function upsertPostcardReaction(pool, reaction) {
  await pool.query(
    `INSERT INTO postcard_reactions (id, postcard_message_id, from_user_id,
      viewed_at, reaction_emoji, comment, reacted_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7)
     ON CONFLICT (postcard_message_id, from_user_id) DO UPDATE SET
       viewed_at = COALESCE(postcard_reactions.viewed_at, EXCLUDED.viewed_at),
       reaction_emoji = COALESCE(EXCLUDED.reaction_emoji, postcard_reactions.reaction_emoji),
       comment = COALESCE(EXCLUDED.comment, postcard_reactions.comment),
       reacted_at = COALESCE(EXCLUDED.reacted_at, postcard_reactions.reacted_at)`,
    [
      reaction.id,
      reaction.postcardMessageID,
      reaction.fromUserID,
      reaction.viewedAt || null,
      reaction.reactionEmoji || null,
      reaction.comment || null,
      reaction.reactedAt || null,
    ]
  );
}

// ============================================================
// Schema Init
// ============================================================

async function ensureSchema(pool) {
  const fs = require("fs");
  const path = require("path");
  const schemaPath = path.join(__dirname, "migrations", "001-create-tables.sql");
  if (fs.existsSync(schemaPath)) {
    const sql = fs.readFileSync(schemaPath, "utf8");
    await pool.query(sql);
  }
}

// ============================================================
// Exports
// ============================================================

module.exports = {
  // Users
  getUserByID,
  getUsersByIDs,
  getUserByEmail,
  getUserByHandle,
  getUserByInviteCode,
  insertUser,
  updateUser,
  deleteUser,
  handleExists,
  displayNameExists,
  getAllUsersOrdered,

  // Auth
  getAuthIdentityByID,
  findAuthIdentityByProviderSubject,
  findEmailPasswordIdentity,
  findVerifiedEmailPasswordIdentity,
  findAuthIdentitiesByUserID,
  insertAuthIdentity,
  updateAuthIdentity,

  // OAuth
  getOAuthUser,
  setOAuthUser,
  transferOAuthEntries,

  // Firebase
  getFirebaseIdentity,
  upsertFirebaseIdentity,

  // Email Verification
  insertEmailVerificationToken,
  findEmailVerificationByHash,
  markEmailVerificationUsed,

  // Password Reset
  insertPasswordResetToken,
  findPasswordResetByHash,
  markPasswordResetUsed,

  // Refresh Tokens
  insertRefreshToken,
  findRefreshTokenByHash,
  revokeRefreshTokensForUser,
  revokeRefreshToken,

  // Friendships
  getFriendIDs,
  areFriends,
  addFriendship,
  removeFriendship,

  // Friend Requests
  getFriendRequest,
  getFriendRequestsTo,
  getFriendRequestsFrom,
  findPendingFriendRequest,
  insertFriendRequest,
  deleteFriendRequest,

  // Journeys
  getJourneysByUser,
  getJourney,
  upsertJourney,
  deleteJourneys,
  deleteAllJourneys,

  // City Cards
  getCityCardsByUser,
  upsertCityCard,
  replaceCityCards,

  // Likes
  getJourneyLikers,
  addJourneyLike,
  removeJourneyLike,
  getJourneyLikeCount,
  hasUserLikedJourney,
  batchGetJourneyLikes,

  // Notifications
  getNotifications,
  insertNotification,
  markNotificationsRead,
  markAllNotificationsRead,

  // Postcards
  getPostcardByID,
  getPostcardsForUser,
  insertPostcard,
  findPostcardByDraft,

  // Postcard Reactions
  getPostcardReaction,
  upsertPostcardReaction,

  // Schema
  ensureSchema,
};
