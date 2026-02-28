const fs = require("fs");
const fsp = require("fs/promises");
const path = require("path");
const crypto = require("crypto");
const express = require("express");
const cors = require("cors");
const jwt = require("jsonwebtoken");
const multer = require("multer");
const { Pool } = require("pg");
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const { OAuth2Client } = require("google-auth-library");
const { createRemoteJWKSet, jwtVerify } = require("jose");

const PORT = Number(process.env.PORT || 18080);
const JWT_SECRET = (process.env.JWT_SECRET || "change-me-in-production").trim();
const DATA_FILE = (process.env.DATA_FILE || "./data/data.json").trim();
const MEDIA_DIR = (process.env.MEDIA_DIR || "./media").trim();
const MEDIA_PUBLIC_BASE = (process.env.MEDIA_PUBLIC_BASE || "").trim();
const DATABASE_URL = (process.env.DATABASE_URL || "").trim();
const PGHOST = (process.env.PGHOST || "").trim();
const PGPORT = Number(process.env.PGPORT || 5432);
const PGUSER = (process.env.PGUSER || "").trim();
const PGPASSWORD = (process.env.PGPASSWORD || "").trim();
const PGDATABASE = (process.env.PGDATABASE || "").trim();
const PGSSL = String(process.env.PGSSL || "").trim().toLowerCase();
const PG_STATE_KEY = (process.env.PG_STATE_KEY || "global").trim();
const PG_MAX_CLIENTS = Number(process.env.PG_MAX_CLIENTS || 10);

const R2_ACCOUNT_ID = (process.env.R2_ACCOUNT_ID || "").trim();
const R2_ACCESS_KEY_ID = (process.env.R2_ACCESS_KEY_ID || "").trim();
const R2_SECRET_ACCESS_KEY = (process.env.R2_SECRET_ACCESS_KEY || "").trim();
const R2_BUCKET = (process.env.R2_BUCKET || "").trim();
const R2_ENDPOINT = (process.env.R2_ENDPOINT || (R2_ACCOUNT_ID ? `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com` : "")).trim();
const R2_REGION = (process.env.R2_REGION || "auto").trim();
const R2_PUBLIC_BASE = (process.env.R2_PUBLIC_BASE || "").trim();
const GOOGLE_CLIENT_ID = (process.env.GOOGLE_CLIENT_ID || "").trim();
const APPLE_AUDIENCES = (process.env.APPLE_AUDIENCES || process.env.APPLE_BUNDLE_ID || "").trim();

const visibilityPrivate = "private";
const visibilityFriendsOnly = "friendsOnly";
const visibilityPublic = "public";

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 50 * 1024 * 1024 } });

const pgEnabled = Boolean(DATABASE_URL || (PGHOST && PGUSER && PGDATABASE));
let pgPool = null;
let pgSchemaReady = false;
if (pgEnabled) {
  const poolConfig = {
    max: Number.isFinite(PG_MAX_CLIENTS) && PG_MAX_CLIENTS > 0 ? PG_MAX_CLIENTS : 10
  };
  if (DATABASE_URL) {
    poolConfig.connectionString = DATABASE_URL;
  } else {
    poolConfig.host = PGHOST;
    poolConfig.port = Number.isFinite(PGPORT) && PGPORT > 0 ? PGPORT : 5432;
    poolConfig.user = PGUSER;
    poolConfig.password = PGPASSWORD;
    poolConfig.database = PGDATABASE;
  }
  if (PGSSL === "require" || PGSSL === "true" || PGSSL === "1") {
    poolConfig.ssl = { rejectUnauthorized: false };
  }
  pgPool = new Pool(poolConfig);
}

let r2Client = null;
if (R2_ACCOUNT_ID && R2_ACCESS_KEY_ID && R2_SECRET_ACCESS_KEY && R2_BUCKET && R2_ENDPOINT) {
  r2Client = new S3Client({
    region: R2_REGION,
    endpoint: R2_ENDPOINT,
    credentials: { accessKeyId: R2_ACCESS_KEY_ID, secretAccessKey: R2_SECRET_ACCESS_KEY },
    forcePathStyle: true
  });
}

const googleOAuthClient = new OAuth2Client();
const appleJWKS = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));
const appleAudienceList = APPLE_AUDIENCES
  .split(",")
  .map((x) => x.trim())
  .filter(Boolean);

function normalizeEmail(raw) {
  const email = String(raw || "").trim().toLowerCase();
  return email.includes("@") ? email : "";
}

function parseTruthy(raw) {
  if (typeof raw === "boolean") return raw;
  const value = String(raw || "").trim().toLowerCase();
  return value === "true" || value === "1";
}

async function verifyGoogleIdentity(idToken) {
  const verifyOptions = { idToken };
  if (GOOGLE_CLIENT_ID) verifyOptions.audience = GOOGLE_CLIENT_ID;
  const ticket = await googleOAuthClient.verifyIdToken(verifyOptions);
  const payload = ticket.getPayload() || {};
  const subject = String(payload.sub || "").trim();
  if (!subject) throw new Error("invalid google token subject");
  const email = normalizeEmail(payload.email);
  const emailVerified = parseTruthy(payload.email_verified);
  return { subject, email, emailVerified };
}

async function verifyAppleIdentity(idToken) {
  const verifyOptions = { issuer: "https://appleid.apple.com" };
  if (appleAudienceList.length === 1) verifyOptions.audience = appleAudienceList[0];
  else if (appleAudienceList.length > 1) verifyOptions.audience = appleAudienceList;
  const { payload } = await jwtVerify(idToken, appleJWKS, verifyOptions);
  const subject = String(payload?.sub || "").trim();
  if (!subject) throw new Error("invalid apple token subject");
  const email = normalizeEmail(payload?.email);
  const emailVerified = parseTruthy(payload?.email_verified);
  return { subject, email, emailVerified };
}

async function verifyOAuthIdentity(provider, idToken) {
  if (provider === "google") return verifyGoogleIdentity(idToken);
  if (provider === "apple") return verifyAppleIdentity(idToken);
  throw new Error("unsupported oauth provider");
}

function nowUnix() {
  return Math.floor(Date.now() / 1000);
}

function randHex(n) {
  return crypto.randomBytes(n).toString("hex");
}

function hashSHA256(raw) {
  return crypto.createHash("sha256").update(raw).digest("hex");
}

function hashPassword(pw) {
  return hashSHA256(`StreetStamps::${pw}`);
}

function genInviteCode() {
  return randHex(4).toUpperCase();
}

function normalizeHandle(raw) {
  const cleaned = String(raw || "")
    .trim()
    .toLowerCase()
    .replace(/^@+/, "")
    .replace(/[^a-z0-9_]/g, "");
  return cleaned.slice(0, 24);
}

function genAutoNumericHandle() {
  return String(Math.floor(Math.random() * 100000000)).padStart(8, "0");
}

function canUseHandle(handle, uid) {
  const owner = db.handleIndex[handle];
  return !owner || owner === uid;
}

function allocateSystemHandle(uid, preferred) {
  const owner = String(uid || "").trim();
  const preferredNormalized = normalizeHandle(preferred);
  if (preferredNormalized && canUseHandle(preferredNormalized, owner)) return preferredNormalized;

  for (let i = 0; i < 500; i += 1) {
    const numeric = genAutoNumericHandle();
    if (canUseHandle(numeric, owner)) return numeric;
  }
  return `${nowUnix()}${Math.floor(Math.random() * 10)}`.slice(-8);
}

function setUserHandle(uid, rawHandle, options = { strict: false }) {
  const owner = String(uid || "").trim();
  const user = db.users[owner];
  if (!user) return { ok: false, code: "user_not_found" };

  let next = "";
  if (options.strict) {
    next = normalizeHandle(rawHandle);
    if (!next) return { ok: false, code: "invalid_handle" };
    if (!canUseHandle(next, owner)) return { ok: false, code: "handle_taken" };
  } else {
    next = allocateSystemHandle(owner, rawHandle);
  }

  const prev = normalizeHandle(user.handle);
  if (prev && prev !== next && db.handleIndex[prev] === owner) {
    delete db.handleIndex[prev];
  }
  user.handle = next;
  db.handleIndex[next] = owner;
  return { ok: true, handle: next };
}

function normalizeVisibility(v) {
  if (v === visibilityPublic || v === visibilityFriendsOnly || v === visibilityPrivate) return v;
  return visibilityPrivate;
}

function normalizeDisplayName(raw) {
  const trimmed = String(raw || "").trim();
  if (!trimmed) return "";
  if (trimmed.length > 24) return "";
  if (/\s/u.test(trimmed)) return "";
  if (/[^\p{L}\p{N}_.-]/u.test(trimmed)) return "";
  return trimmed;
}

function normalizeISOTime(raw) {
  const t = Date.parse(String(raw || ""));
  if (!Number.isFinite(t)) return null;
  return new Date(t).toISOString();
}

function normalizeRouteCoordinates(raw) {
  const src = Array.isArray(raw) ? raw : [];
  const out = [];
  for (const item of src) {
    const lat = Number(item && item.lat);
    const lon = Number(item && item.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) continue;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;
    out.push({ lat, lon });
    if (out.length >= 50000) break;
  }
  return out;
}

function normalizeJourneyMemories(rawMemories) {
  const src = Array.isArray(rawMemories) ? rawMemories : [];
  return src.map((m) => ({
    id: String(m?.id || `m_${randHex(8)}`),
    title: String(m?.title || "").slice(0, 120),
    notes: String(m?.notes || "").slice(0, 4000),
    timestamp: normalizeISOTime(m?.timestamp) || new Date().toISOString(),
    imageURLs: Array.isArray(m?.imageURLs) ? m.imageURLs.map((x) => String(x || "")).filter(Boolean).slice(0, 32) : []
  }));
}

function normalizeJourneyPayload(raw) {
  return {
    id: String(raw?.id || `j_${randHex(8)}`),
    title: String(raw?.title || "Journey").slice(0, 120),
    activityTag: raw?.activityTag == null ? null : String(raw.activityTag).slice(0, 32),
    overallMemory: raw?.overallMemory == null ? null : String(raw.overallMemory).slice(0, 4000),
    distance: Number(raw?.distance || 0),
    startTime: normalizeISOTime(raw?.startTime),
    endTime: normalizeISOTime(raw?.endTime),
    visibility: normalizeVisibility(raw?.visibility),
    routeCoordinates: normalizeRouteCoordinates(raw?.routeCoordinates || raw?.coordinates),
    memories: normalizeJourneyMemories(raw?.memories)
  };
}

function safeExt(fileName) {
  const ext = path.extname(fileName || "").toLowerCase();
  const allowed = new Set([".jpg", ".jpeg", ".png", ".webp", ".heic", ".gif", ".mp4", ".mov"]);
  return allowed.has(ext) ? ext : ".bin";
}

function appendUnique(ids, id) {
  if (!ids.includes(id)) ids.push(id);
  return ids;
}

function removeID(ids, id) {
  return ids.filter((x) => x !== id);
}

function defaultLoadout() {
  return {
    bodyId: "body",
    headId: "head",
    skinId: "skin_default",
    hairId: "hair_boy_default",
    outfitId: "outfit_boy_suit",
    accessoryIds: ["acc_headphone"],
    expressionId: "expr_default"
  };
}

function profileStatsFrom(user) {
  const journeys = user.journeys || [];
  return {
    totalJourneys: journeys.length,
    totalDistance: journeys.reduce((acc, j) => acc + Number(j.distance || 0), 0),
    totalMemories: journeys.reduce((acc, j) => acc + ((j.memories || []).length), 0),
    totalUnlockedCities: (user.cityCards || []).length
  };
}

function seedDemoJourneys() {
  const now = Date.now();
  const t1 = new Date(now - 48 * 60 * 60 * 1000).toISOString();
  const t2 = new Date(now - 47.5 * 60 * 60 * 1000).toISOString();
  const m1 = new Date(now - 47 * 60 * 60 * 1000).toISOString();
  return [
    {
      id: `j_${randHex(8)}`,
      title: "City Walk",
      activityTag: "步行",
      overallMemory: "在城市里慢慢走，拍到了很多街角光影。",
      distance: 6200,
      startTime: t1,
      endTime: t2,
      visibility: visibilityPublic,
      routeCoordinates: [
        { lat: 31.2304, lon: 121.4737 },
        { lat: 31.2320, lon: 121.4801 },
        { lat: 31.2343, lon: 121.4858 }
      ],
      memories: [{ id: `m_${randHex(8)}`, title: "街边咖啡", notes: "转角那家店的拿铁很稳。", timestamp: m1, imageURLs: [] }]
    }
  ];
}

function seedDemoCityCards() {
  return [
    { id: "Shanghai|CN", name: "Shanghai", countryISO2: "CN" },
    { id: "Hangzhou|CN", name: "Hangzhou", countryISO2: "CN" }
  ];
}

function makeAccessToken(uid, provider) {
  return jwt.sign({ uid, prv: provider, typ: "access" }, JWT_SECRET, { expiresIn: "2h" });
}

function makeRefreshToken(uid, provider) {
  return jwt.sign({ uid, prv: provider, typ: "refresh" }, JWT_SECRET, { expiresIn: "30d" });
}

function parseBearer(req) {
  const h = req.headers.authorization || "";
  if (!h.startsWith("Bearer ")) throw new Error("missing bearer");
  const tok = h.slice(7).trim();
  const payload = jwt.verify(tok, JWT_SECRET);
  if (!payload || payload.typ !== "access") throw new Error("invalid token");
  return payload.uid;
}

function parseRefreshToken(rawToken) {
  const tok = String(rawToken || "").trim();
  if (!tok) throw new Error("missing refresh token");
  const payload = jwt.verify(tok, JWT_SECRET);
  if (!payload || payload.typ !== "refresh") throw new Error("invalid refresh token");
  return payload;
}

function emptyDB() {
  return { users: {}, emailIndex: {}, inviteIndex: {}, oauthIndex: {}, handleIndex: {}, likesIndex: {}, friendRequestsIndex: {} };
}

function normalizeDBShape(parsed) {
  return {
    users: parsed?.users || {},
    emailIndex: parsed?.emailIndex || {},
    inviteIndex: parsed?.inviteIndex || {},
    oauthIndex: parsed?.oauthIndex || {},
    handleIndex: parsed?.handleIndex || {},
    likesIndex: parsed?.likesIndex || {},
    friendRequestsIndex: parsed?.friendRequestsIndex || {}
  };
}

function hasPersistedData(parsed) {
  const src = parsed || {};
  const keys = ["users", "emailIndex", "inviteIndex", "oauthIndex", "handleIndex", "likesIndex", "friendRequestsIndex"];
  return keys.some((k) => src[k] && Object.keys(src[k]).length > 0);
}

async function ensureDirForFile(filePath) {
  await fsp.mkdir(path.dirname(filePath), { recursive: true });
}

async function loadDBFromFile() {
  try {
    const raw = await fsp.readFile(DATA_FILE, "utf8");
    if (!raw.trim()) return emptyDB();
    return normalizeDBShape(JSON.parse(raw));
  } catch (e) {
    if (e && e.code === "ENOENT") return emptyDB();
    throw e;
  }
}

async function ensurePGSchema() {
  if (!pgPool || pgSchemaReady) return;
  await pgPool.query(`
    CREATE TABLE IF NOT EXISTS app_state (
      key TEXT PRIMARY KEY,
      state JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  pgSchemaReady = true;
}

async function loadDBFromPostgres() {
  if (!pgPool) return null;
  await ensurePGSchema();
  const result = await pgPool.query("SELECT state FROM app_state WHERE key = $1 LIMIT 1", [PG_STATE_KEY]);
  if (!result.rows.length) return null;
  return normalizeDBShape(result.rows[0]?.state || {});
}

async function saveDBToPostgres(nextDB) {
  if (!pgPool) return;
  await ensurePGSchema();
  await pgPool.query(
    `INSERT INTO app_state (key, state, updated_at)
     VALUES ($1, $2::jsonb, NOW())
     ON CONFLICT (key)
     DO UPDATE SET state = EXCLUDED.state, updated_at = NOW()`,
    [PG_STATE_KEY, JSON.stringify(nextDB || emptyDB())]
  );
}

async function loadDB() {
  if (!pgPool) return loadDBFromFile();
  const fromPG = await loadDBFromPostgres();
  if (fromPG) return fromPG;

  const fromFile = await loadDBFromFile();
  if (hasPersistedData(fromFile)) {
    await saveDBToPostgres(fromFile);
  }
  return fromFile;
}

let db = emptyDB();
let writeChain = Promise.resolve();

function saveDB() {
  writeChain = writeChain.then(async () => {
    if (pgPool) {
      await saveDBToPostgres(db);
      return;
    }
    await ensureDirForFile(DATA_FILE);
    await fsp.writeFile(DATA_FILE, JSON.stringify(db, null, 2), "utf8");
  });
  return writeChain;
}

function filterJourneys(journeys, isSelf, isFriend) {
  if (isSelf) return journeys;
  const out = [];
  for (const j of journeys || []) {
    const v = normalizeVisibility(j.visibility);
    if (v === visibilityPublic) out.push(j);
    if (v === visibilityFriendsOnly && isFriend) out.push(j);
  }
  return out;
}

function canViewJourney(viewer, owner, journey) {
  const isSelf = viewer && owner && viewer.id === owner.id;
  if (isSelf) return true;
  const isFriend = viewer && owner ? isFriendOf(viewer, owner.id) : false;
  const v = normalizeVisibility(journey?.visibility);
  if (v === visibilityPublic) return true;
  if (v === visibilityFriendsOnly && isFriend) return true;
  return false;
}

function journeyLikeKey(ownerUserID, journeyID) {
  return `${ownerUserID}:${journeyID}`;
}

function ensureLikeRecord(ownerUserID, journeyID) {
  const key = journeyLikeKey(ownerUserID, journeyID);
  if (!db.likesIndex[key]) {
    db.likesIndex[key] = {
      ownerUserID,
      journeyID,
      likerIDs: [],
      updatedAt: new Date().toISOString()
    };
  }
  if (!Array.isArray(db.likesIndex[key].likerIDs)) db.likesIndex[key].likerIDs = [];
  return db.likesIndex[key];
}

function ensureUserNotifications(user) {
  if (!Array.isArray(user.notifications)) user.notifications = [];
}

function pushJourneyLikeNotification(owner, fromUser, journey) {
  ensureUserNotifications(owner);
  owner.notifications.unshift({
    id: `n_${randHex(10)}`,
    type: "journey_like",
    fromUserID: fromUser.id,
    fromDisplayName: fromUser.displayName,
    journeyID: journey.id,
    journeyTitle: journey.title,
    message: `${fromUser.displayName} liked your journey "${journey.title}"`,
    createdAt: new Date().toISOString(),
    read: false
  });
  if (owner.notifications.length > 400) {
    owner.notifications = owner.notifications.slice(0, 400);
  }
}

function pushProfileStompNotification(owner, fromUser) {
  ensureUserNotifications(owner);
  owner.notifications.unshift({
    id: `n_${randHex(10)}`,
    type: "profile_stomp",
    fromUserID: fromUser.id,
    fromDisplayName: fromUser.displayName,
    journeyID: null,
    journeyTitle: null,
    message: `${fromUser.displayName} 踩了踩你的主页`,
    createdAt: new Date().toISOString(),
    read: false
  });
  if (owner.notifications.length > 400) {
    owner.notifications = owner.notifications.slice(0, 400);
  }
}

function pushFriendRequestNotification(owner, fromUser) {
  ensureUserNotifications(owner);
  owner.notifications.unshift({
    id: `n_${randHex(10)}`,
    type: "friend_request",
    fromUserID: fromUser.id,
    fromDisplayName: fromUser.displayName,
    journeyID: null,
    journeyTitle: null,
    message: `${fromUser.displayName} 向你发送了好友申请`,
    createdAt: new Date().toISOString(),
    read: false
  });
  if (owner.notifications.length > 400) {
    owner.notifications = owner.notifications.slice(0, 400);
  }
}

function pushFriendRequestAcceptedNotification(owner, fromUser) {
  ensureUserNotifications(owner);
  owner.notifications.unshift({
    id: `n_${randHex(10)}`,
    type: "friend_request_accepted",
    fromUserID: fromUser.id,
    fromDisplayName: fromUser.displayName,
    journeyID: null,
    journeyTitle: null,
    message: `${fromUser.displayName} 通过了你的好友申请`,
    createdAt: new Date().toISOString(),
    read: false
  });
  if (owner.notifications.length > 400) {
    owner.notifications = owner.notifications.slice(0, 400);
  }
}

function isFriendOf(viewer, targetID) {
  return (viewer.friendIDs || []).includes(targetID);
}

function friendRequestUserDTO(user) {
  return {
    id: user.id,
    displayName: user.displayName,
    handle: user.handle || null,
    exclusiveID: user.handle || null,
    loadout: user.loadout || defaultLoadout()
  };
}

function friendRequestDTO(request) {
  const from = db.users[request.fromUserID];
  const to = db.users[request.toUserID];
  if (!from || !to) return null;
  return {
    id: request.id,
    fromUserID: request.fromUserID,
    toUserID: request.toUserID,
    fromUser: friendRequestUserDTO(from),
    toUser: friendRequestUserDTO(to),
    note: request.note || "",
    createdAt: request.createdAt
  };
}

function allFriendRequests() {
  return Object.values(db.friendRequestsIndex || {}).filter((x) => x && x.id && x.fromUserID && x.toUserID);
}

function sortByCreatedDesc(requests) {
  return requests.sort((a, b) => Date.parse(b.createdAt || "") - Date.parse(a.createdAt || ""));
}

function findPendingFriendRequest(fromUserID, toUserID) {
  return allFriendRequests().find((item) => item.fromUserID === fromUserID && item.toUserID === toUserID) || null;
}

function removeFriendRequestByID(requestID) {
  if (!requestID) return;
  if (db.friendRequestsIndex && db.friendRequestsIndex[requestID]) {
    delete db.friendRequestsIndex[requestID];
  }
}

function removeFriendRequestsBetween(userA, userB) {
  for (const req of allFriendRequests()) {
    const sameDirection = req.fromUserID === userA && req.toUserID === userB;
    const reverseDirection = req.fromUserID === userB && req.toUserID === userA;
    if (sameDirection || reverseDirection) {
      delete db.friendRequestsIndex[req.id];
    }
  }
}

function profileDTOForViewer(target, isSelf, isFriend) {
  const visibility = target.profileVisibility || visibilityFriendsOnly;
  const blocked = !isSelf && visibility === visibilityPrivate;
  const journeys = blocked ? [] : filterJourneys(target.journeys || [], isSelf, isFriend);
  const cards = blocked ? [] : (isSelf || isFriend ? (target.cityCards || []) : []);

  return {
    id: target.id,
    handle: target.handle || null,
    exclusiveID: target.handle || null,
    inviteCode: target.inviteCode,
    profileVisibility: visibility,
    displayName: target.displayName,
    email: isSelf ? (target.email || null) : null,
    bio: target.bio,
    loadout: target.loadout,
    handleChangeUsed: Boolean(target.handleChangeUsed),
    canUpdateHandleOneTime: !target.handleChangeUsed,
    stats: profileStatsFrom(target),
    journeys,
    unlockedCityCards: cards
  };
}

function friendDTOForViewer(u, isFriend) {
  return profileDTOForViewer(u, false, isFriend);
}

async function uploadToR2OrThrow(objectKey, body, contentType) {
  if (!r2Client) throw new Error("r2 disabled");
  await r2Client.send(new PutObjectCommand({
    Bucket: R2_BUCKET,
    Key: objectKey,
    Body: body,
    ContentType: contentType || "application/octet-stream"
  }));
}

function r2PublicURL(objectKey) {
  const base = R2_PUBLIC_BASE || R2_ENDPOINT;
  if (!base) return null;
  const b = base.replace(/\/$/, "");
  if (R2_PUBLIC_BASE) return `${b}/${objectKey}`;
  return `${b}/${R2_BUCKET}/${objectKey}`;
}

async function main() {
  db = await loadDB();
  console.log(`[streetstamps-node-v1] storage=${pgPool ? "postgresql" : "file"}`);
  db.handleIndex = {};
  if (!db.likesIndex || typeof db.likesIndex !== "object") {
    db.likesIndex = {};
  }
  if (!db.friendRequestsIndex || typeof db.friendRequestsIndex !== "object") {
    db.friendRequestsIndex = {};
  }
  for (const [uid, user] of Object.entries(db.users || {})) {
    setUserHandle(uid, user.handle || user.displayName || uid, { strict: false });
    if (!user.profileVisibility) user.profileVisibility = visibilityFriendsOnly;
    if (typeof user.handleChangeUsed !== "boolean") {
      user.handleChangeUsed = false;
    }
    ensureUserNotifications(user);
  }
  for (const req of allFriendRequests()) {
    const from = db.users[req.fromUserID];
    const to = db.users[req.toUserID];
    if (!from || !to || from.id === to.id || isFriendOf(from, to.id)) {
      delete db.friendRequestsIndex[req.id];
    }
  }
  await fsp.mkdir(MEDIA_DIR, { recursive: true });

  const app = express();
  app.use(cors({ origin: "*" }));
  app.use(express.json({ limit: "20mb" }));
  app.use("/media", express.static(MEDIA_DIR));

  app.get("/v1/health", (_req, res) => res.status(200).json({ status: "ok" }));

  app.post("/v1/auth/email/register", async (req, res) => {
    try {
      const email = String(req.body?.email || "").trim().toLowerCase();
      const password = String(req.body?.password || "");
      if (!email.includes("@") || password.length < 8) return res.status(400).json({ message: "invalid email or password" });
      if (db.emailIndex[email]) return res.status(409).json({ message: "email already exists" });

      const uid = `u_${randHex(12)}`;
      const invite = genInviteCode();
      const user = {
        id: uid,
        provider: "email",
        email,
        passwordHash: hashPassword(password),
        inviteCode: invite,
        handle: null,
        handleChangeUsed: false,
        profileVisibility: visibilityFriendsOnly,
        displayName: "Explorer",
        bio: "Travel Enthusiastic",
        loadout: defaultLoadout(),
        journeys: [],
        cityCards: [],
        friendIDs: [],
        notifications: [],
        createdAt: nowUnix()
      };
      db.users[uid] = user;
      setUserHandle(uid, null, { strict: false });
      db.emailIndex[email] = uid;
      db.inviteIndex[invite] = uid;
      await saveDB();

      return res.status(200).json({ userId: uid, provider: "email", email, accessToken: makeAccessToken(uid, "email"), refreshToken: makeRefreshToken(uid, "email") });
    } catch (e) {
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.post("/v1/auth/email/login", (req, res) => {
    try {
      const email = String(req.body?.email || "").trim().toLowerCase();
      const password = String(req.body?.password || "");
      const uid = db.emailIndex[email];
      if (!uid) return res.status(404).json({ message: "account not found" });
      const u = db.users[uid];
      if (!u || u.passwordHash !== hashPassword(password)) return res.status(401).json({ message: "wrong email or password" });
      return res.status(200).json({ userId: uid, provider: u.provider, email: u.email || null, accessToken: makeAccessToken(uid, u.provider), refreshToken: makeRefreshToken(uid, u.provider) });
    } catch {
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.post("/v1/auth/oauth", async (req, res) => {
    try {
      const provider = String(req.body?.provider || "").trim().toLowerCase();
      const idToken = String(req.body?.idToken || "").trim();
      if (provider !== "apple" && provider !== "google") return res.status(400).json({ message: "provider must be apple or google" });
      if (!idToken) return res.status(400).json({ message: "idToken required" });
      const identity = await verifyOAuthIdentity(provider, idToken);
      const key = `${provider}:${identity.subject}`;
      let uid = db.oauthIndex[key];
      let changed = false;

      if (!uid && identity.email && identity.emailVerified) {
        const emailUID = db.emailIndex[identity.email];
        if (emailUID && db.users[emailUID]) {
          uid = emailUID;
        }
      }

      if (!uid) {
        uid = `u_${randHex(12)}`;
        const invite = genInviteCode();
        db.users[uid] = {
          id: uid,
          provider,
          inviteCode: invite,
          handle: null,
          handleChangeUsed: false,
          profileVisibility: visibilityFriendsOnly,
          displayName: "Explorer",
          bio: "Travel Enthusiastic",
          loadout: defaultLoadout(),
          journeys: [],
          cityCards: [],
          friendIDs: [],
          notifications: [],
          createdAt: nowUnix()
        };
        setUserHandle(uid, null, { strict: false });
        db.inviteIndex[invite] = uid;
        changed = true;
      }

      if (db.oauthIndex[key] !== uid) {
        db.oauthIndex[key] = uid;
        changed = true;
      }

      const u = db.users[uid];
      if (!u) return res.status(500).json({ message: "user not found after oauth login" });

      if (identity.email && identity.emailVerified) {
        if (!u.email) {
          u.email = identity.email;
          changed = true;
        }
        if (!db.emailIndex[identity.email]) {
          db.emailIndex[identity.email] = uid;
          changed = true;
        }
      }

      if (changed) {
        await saveDB();
      }
      return res.status(200).json({ userId: uid, provider: u.provider, email: u.email || null, accessToken: makeAccessToken(uid, u.provider), refreshToken: makeRefreshToken(uid, u.provider) });
    } catch (e) {
      const message = String(e?.message || "").toLowerCase();
      if (message.includes("token") || message.includes("jwt") || message.includes("audience") || message.includes("issuer")) {
        return res.status(401).json({ message: "invalid oauth token" });
      }
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.post("/v1/auth/refresh", (req, res) => {
    try {
      const payload = parseRefreshToken(req.body?.refreshToken);
      const uid = String(payload?.uid || "").trim();
      if (!uid) return res.status(401).json({ message: "unauthorized" });

      const u = db.users[uid];
      if (!u) return res.status(401).json({ message: "unauthorized" });

      return res.status(200).json({
        userId: uid,
        provider: u.provider,
        email: u.email || null,
        accessToken: makeAccessToken(uid, u.provider),
        refreshToken: makeRefreshToken(uid, u.provider)
      });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.get("/v1/friends", (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });
      const out = [];
      for (const fid of me.friendIDs || []) {
        const f = db.users[fid];
        if (f) out.push(friendDTOForViewer(f, true));
      }
      return res.status(200).json(out);
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/friends", async (req, res) => {
    try {
      const uid = parseBearer(req);
      if (!db.users[uid]) return res.status(404).json({ message: "user not found" });
      return res.status(409).json({ message: "direct add disabled, use /v1/friends/requests" });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.get("/v1/friends/requests", (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });

      const incoming = sortByCreatedDesc(
        allFriendRequests().filter((item) => item.toUserID === uid).map(friendRequestDTO).filter(Boolean)
      );
      const outgoing = sortByCreatedDesc(
        allFriendRequests().filter((item) => item.fromUserID === uid).map(friendRequestDTO).filter(Boolean)
      );
      return res.status(200).json({ incoming, outgoing });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/friends/requests", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });

      const displayName = String(req.body?.displayName || "").trim();
      const handleRaw = String(req.body?.handle || req.body?.exclusiveID || "").trim();
      const inviteCodeRaw = req.body?.inviteCode == null ? "" : String(req.body.inviteCode).trim();
      const note = String(req.body?.note || displayName || "").trim().slice(0, 120);
      if (!displayName && !inviteCodeRaw && !handleRaw) {
        return res.status(400).json({ message: "displayName or inviteCode or exclusiveID required" });
      }

      let target = null;
      if (inviteCodeRaw) {
        const code = inviteCodeRaw.toUpperCase();
        const targetID = db.inviteIndex[code];
        if (targetID) target = db.users[targetID] || null;
      }
      const requestedHandle = normalizeHandle(handleRaw || displayName);
      if (!target && requestedHandle) {
        const targetID = db.handleIndex[requestedHandle];
        if (targetID) target = db.users[targetID] || null;
      }

      if (!target) {
        if (inviteCodeRaw) {
          return res.status(404).json({ message: "invite code not found" });
        }
        if (requestedHandle) {
          return res.status(404).json({ message: "exclusive id not found" });
        }
        return res.status(400).json({ message: "use inviteCode or exclusiveID to add friend" });
      }

      if (target.id === me.id) {
        return res.status(400).json({ message: "cannot add yourself" });
      }

      if ((me.friendIDs || []).includes(target.id)) {
        return res.status(409).json({ message: "already friends" });
      }

      const existing = findPendingFriendRequest(uid, target.id);
      if (existing) {
        const dto = friendRequestDTO(existing);
        return res.status(200).json({ ok: true, request: dto, message: "好友申请已发送，等待对方通过" });
      }

      const reverse = findPendingFriendRequest(target.id, uid);
      if (reverse) {
        return res.status(409).json({ message: "对方已向你发送申请，请在申请列表中通过" });
      }

      const reqID = `fr_${randHex(10)}`;
      const createdAt = new Date().toISOString();
      db.friendRequestsIndex[reqID] = {
        id: reqID,
        fromUserID: uid,
        toUserID: target.id,
        note,
        createdAt,
        updatedAt: createdAt
      };
      pushFriendRequestNotification(target, me);
      await saveDB();
      return res.status(200).json({
        ok: true,
        request: friendRequestDTO(db.friendRequestsIndex[reqID]),
        message: "好友申请已发送，等待对方通过"
      });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/friends/requests/:requestID/accept", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });
      const requestID = String(req.params.requestID || "").trim();
      if (!requestID) return res.status(400).json({ message: "request id required" });

      const pending = db.friendRequestsIndex[requestID];
      if (!pending) return res.status(404).json({ message: "request not found" });
      if (pending.toUserID !== uid) return res.status(403).json({ message: "forbidden" });

      const fromUser = db.users[pending.fromUserID];
      if (!fromUser) {
        removeFriendRequestByID(requestID);
        await saveDB();
        return res.status(404).json({ message: "request sender not found" });
      }

      appendUnique(me.friendIDs, fromUser.id);
      appendUnique(fromUser.friendIDs, me.id);
      removeFriendRequestsBetween(me.id, fromUser.id);
      pushFriendRequestAcceptedNotification(fromUser, me);
      await saveDB();
      return res.status(200).json({
        ok: true,
        friend: friendDTOForViewer(fromUser, true),
        message: "已通过好友申请"
      });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/friends/requests/:requestID/reject", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });
      const requestID = String(req.params.requestID || "").trim();
      if (!requestID) return res.status(400).json({ message: "request id required" });

      const pending = db.friendRequestsIndex[requestID];
      if (!pending) return res.status(404).json({ message: "request not found" });
      if (pending.toUserID !== uid) return res.status(403).json({ message: "forbidden" });

      removeFriendRequestByID(requestID);
      await saveDB();
      return res.status(200).json({ ok: true, message: "已拒绝好友申请" });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.delete("/v1/friends/:friendID", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });
      const fid = String(req.params.friendID || "").trim();
      if (!fid) return res.status(400).json({ message: "friend id required" });

      me.friendIDs = removeID(me.friendIDs || [], fid);
      const f = db.users[fid];
      if (f) f.friendIDs = removeID(f.friendIDs || [], uid);
      removeFriendRequestsBetween(uid, fid);
      await saveDB();
      return res.status(200).json({});
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/journeys/migrate", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });
      const journeys = Array.isArray(req.body?.journeys) ? req.body.journeys : [];
      const unlockedCityCards = Array.isArray(req.body?.unlockedCityCards) ? req.body.unlockedCityCards : [];
      me.journeys = journeys.map(normalizeJourneyPayload);
      me.cityCards = unlockedCityCards;
      await saveDB();
      return res.status(200).json({ journeys: me.journeys.length, cityCards: me.cityCards.length });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/journeys/likes/batch", (req, res) => {
    try {
      const viewerID = parseBearer(req);
      const viewer = db.users[viewerID];
      if (!viewer) return res.status(404).json({ message: "user not found" });

      const ownerUserIDRaw = String(req.body?.ownerUserID || "").trim();
      const ownerUserID = ownerUserIDRaw || viewerID;
      const owner = db.users[ownerUserID];
      if (!owner) return res.status(404).json({ message: "user not found" });

      const ids = Array.isArray(req.body?.journeyIDs)
        ? req.body.journeyIDs.map((x) => String(x || "").trim()).filter(Boolean)
        : [];
      const uniqIDs = [...new Set(ids)];

      const ownerJourneyByID = new Map((owner.journeys || []).map((j) => [String(j.id), j]));
      const items = [];
      for (const journeyID of uniqIDs) {
        const journey = ownerJourneyByID.get(journeyID);
        if (!journey) {
          items.push({ journeyID, likes: 0, likedByMe: false });
          continue;
        }
        if (!canViewJourney(viewer, owner, journey)) {
          items.push({ journeyID, likes: 0, likedByMe: false });
          continue;
        }
        const record = ensureLikeRecord(ownerUserID, journeyID);
        const likerIDs = Array.isArray(record.likerIDs) ? record.likerIDs : [];
        items.push({
          journeyID,
          likes: likerIDs.length,
          likedByMe: likerIDs.includes(viewerID)
        });
      }
      return res.status(200).json({ items });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/journeys/:ownerUserID/:journeyID/like", async (req, res) => {
    try {
      const viewerID = parseBearer(req);
      const ownerUserID = String(req.params.ownerUserID || "").trim();
      const journeyID = String(req.params.journeyID || "").trim();
      if (!ownerUserID || !journeyID) return res.status(400).json({ message: "ownerUserID and journeyID required" });

      const viewer = db.users[viewerID];
      const owner = db.users[ownerUserID];
      if (!viewer || !owner) return res.status(404).json({ message: "user not found" });
      const journey = (owner.journeys || []).find((x) => String(x.id) === journeyID);
      if (!journey) return res.status(404).json({ message: "journey not found" });
      if (!canViewJourney(viewer, owner, journey)) return res.status(403).json({ message: "forbidden" });

      const record = ensureLikeRecord(ownerUserID, journeyID);
      if (!record.likerIDs.includes(viewerID)) {
        record.likerIDs.push(viewerID);
        record.updatedAt = new Date().toISOString();
        if (viewerID !== ownerUserID) {
          pushJourneyLikeNotification(owner, viewer, journey);
        }
        await saveDB();
      }

      return res.status(200).json({
        ownerUserID,
        journeyID,
        likes: record.likerIDs.length,
        likedByMe: true
      });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.delete("/v1/journeys/:ownerUserID/:journeyID/like", async (req, res) => {
    try {
      const viewerID = parseBearer(req);
      const ownerUserID = String(req.params.ownerUserID || "").trim();
      const journeyID = String(req.params.journeyID || "").trim();
      if (!ownerUserID || !journeyID) return res.status(400).json({ message: "ownerUserID and journeyID required" });

      const owner = db.users[ownerUserID];
      if (!owner) return res.status(404).json({ message: "user not found" });
      const record = ensureLikeRecord(ownerUserID, journeyID);
      const next = (record.likerIDs || []).filter((x) => x !== viewerID);
      if (next.length !== (record.likerIDs || []).length) {
        record.likerIDs = next;
        record.updatedAt = new Date().toISOString();
        await saveDB();
      }
      return res.status(200).json({
        ownerUserID,
        journeyID,
        likes: (record.likerIDs || []).length,
        likedByMe: false
      });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.get("/v1/notifications", (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });
      ensureUserNotifications(me);
      const unreadOnlyRaw = String(req.query.unreadOnly || "1").trim().toLowerCase();
      const unreadOnly = !(unreadOnlyRaw === "0" || unreadOnlyRaw === "false" || unreadOnlyRaw === "no");
      const source = me.notifications || [];
      const items = unreadOnly ? source.filter((x) => !x.read) : source;
      return res.status(200).json({ items });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/notifications/read", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });
      ensureUserNotifications(me);

      const markAll = Boolean(req.body?.all);
      const ids = Array.isArray(req.body?.ids)
        ? req.body.ids.map((x) => String(x || "").trim()).filter(Boolean)
        : [];
      const idSet = new Set(ids);

      let changed = false;
      me.notifications = (me.notifications || []).map((item) => {
        const shouldRead = markAll || idSet.has(String(item.id));
        if (shouldRead && !item.read) {
          changed = true;
          return { ...item, read: true };
        }
        return item;
      });

      if (changed) await saveDB();
      return res.status(200).json({ ok: true });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.get("/v1/profile/me", (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });
      return res.status(200).json(profileDTOForViewer(me, true, true));
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/profile/:userID/stomp", async (req, res) => {
    try {
      const viewerID = parseBearer(req);
      const targetID = String(req.params.userID || "").trim();
      if (!targetID) return res.status(400).json({ message: "target user id required" });

      const viewer = db.users[viewerID];
      const target = db.users[targetID];
      if (!viewer || !target) return res.status(404).json({ message: "user not found" });
      if (viewerID === targetID) return res.status(400).json({ message: "cannot stomp yourself" });
      if (!isFriendOf(viewer, targetID)) return res.status(403).json({ message: "friends only" });

      pushProfileStompNotification(target, viewer);
      await saveDB();
      return res.status(200).json({ ok: true, message: `已踩一踩 ${target.displayName} 的主页` });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  const updateExclusiveID = async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });

      const incoming = String(req.body?.exclusiveID || req.body?.handle || "").trim();
      const current = normalizeHandle(me.handle);
      const next = normalizeHandle(incoming);
      if (!next) {
        return res.status(400).json({ message: "invalid exclusive id" });
      }
      if (next === current) {
        return res.status(200).json(profileDTOForViewer(me, true, true));
      }
      if (me.handleChangeUsed) {
        return res.status(403).json({ message: "exclusive id can only be changed once" });
      }

      const updated = setUserHandle(uid, incoming, { strict: true });
      if (!updated.ok) {
        if (updated.code === "invalid_handle") {
          return res.status(400).json({ message: "invalid exclusive id" });
        }
        if (updated.code === "handle_taken") {
          return res.status(409).json({ message: "exclusive id already taken" });
        }
        return res.status(400).json({ message: "exclusive id update failed" });
      }

      me.handleChangeUsed = true;
      await saveDB();
      return res.status(200).json(profileDTOForViewer(me, true, true));
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  };

  app.patch("/v1/profile/exclusive-id", updateExclusiveID);
  app.patch("/v1/profile/handle", updateExclusiveID);

  app.patch("/v1/profile/display-name", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });

      const nextName = normalizeDisplayName(req.body?.displayName);
      if (!nextName) return res.status(400).json({ message: "invalid display name" });

      me.displayName = nextName;
      await saveDB();
      return res.status(200).json(profileDTOForViewer(me, true, true));
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.patch("/v1/profile/visibility", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });

      const next = normalizeVisibility(req.body?.profileVisibility);
      me.profileVisibility = next;
      await saveDB();
      return res.status(200).json(profileDTOForViewer(me, true, true));
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.patch("/v1/profile/bio", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });

      const bio = String(req.body?.bio || "").slice(0, 200);
      me.bio = bio;
      await saveDB();
      return res.status(200).json(profileDTOForViewer(me, true, true));
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.patch("/v1/profile/loadout", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });

      const incoming = req.body?.loadout;
      if (!incoming || typeof incoming !== "object" || Array.isArray(incoming)) {
        return res.status(400).json({ message: "invalid loadout" });
      }

      me.loadout = {
        bodyId: String(incoming.bodyId || me.loadout?.bodyId || "body"),
        headId: String(incoming.headId || me.loadout?.headId || "head"),
        hairId: String(incoming.hairId || me.loadout?.hairId || "hair_boy_default"),
        outfitId: String(incoming.outfitId || me.loadout?.outfitId || "outfit_boy_suit"),
        accessoryId: incoming.accessoryId == null ? null : String(incoming.accessoryId),
        expressionId: String(incoming.expressionId || me.loadout?.expressionId || "expr_default")
      };
      await saveDB();
      return res.status(200).json(profileDTOForViewer(me, true, true));
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.get("/v1/profile/:userID", (req, res) => {
    try {
      const viewerID = parseBearer(req);
      const targetID = String(req.params.userID || "").trim();
      if (!targetID || targetID === "me") {
        const me = db.users[viewerID];
        if (!me) return res.status(404).json({ message: "user not found" });
        return res.status(200).json(profileDTOForViewer(me, true, true));
      }

      const viewer = db.users[viewerID];
      const target = db.users[targetID];
      if (!viewer || !target) return res.status(404).json({ message: "user not found" });

      const isSelf = viewerID === targetID;
      const isFriend = isFriendOf(viewer, targetID);
      return res.status(200).json(profileDTOForViewer(target, isSelf, isFriend));
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/media/upload", upload.single("file"), async (req, res) => {
    try {
      const uid = parseBearer(req);
      if (!db.users[uid]) return res.status(404).json({ message: "user not found" });
      if (!req.file || !req.file.buffer) return res.status(400).json({ message: "file required" });

      const ext = safeExt(req.file.originalname);
      const objectKey = `${uid}/${randHex(16)}${ext}`;

      if (r2Client) {
        try {
          await uploadToR2OrThrow(objectKey, req.file.buffer, req.file.mimetype);
          const url = r2PublicURL(objectKey);
          if (url) return res.status(200).json({ objectKey, url });
        } catch (e) {
          console.error("r2 upload failed, fallback to local disk:", e && e.message ? e.message : e);
        }
      }

      const fullPath = path.join(MEDIA_DIR, objectKey);
      await fsp.mkdir(path.dirname(fullPath), { recursive: true });
      await fsp.writeFile(fullPath, req.file.buffer);
      const url = MEDIA_PUBLIC_BASE ? `${MEDIA_PUBLIC_BASE.replace(/\/$/, "")}/media/${objectKey}` : `/media/${objectKey}`;
      return res.status(200).json({ objectKey, url });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.listen(PORT, () => {
    console.log(`[streetstamps-node-v1] listening on :${PORT}`);
  });
}

main().catch((e) => {
  console.error("fatal:", e);
  process.exit(1);
});
