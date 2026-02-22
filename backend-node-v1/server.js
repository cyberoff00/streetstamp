const fs = require("fs");
const fsp = require("fs/promises");
const path = require("path");
const crypto = require("crypto");
const express = require("express");
const cors = require("cors");
const jwt = require("jsonwebtoken");
const multer = require("multer");
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const { OAuth2Client } = require("google-auth-library");
const { createRemoteJWKSet, jwtVerify } = require("jose");

const PORT = Number(process.env.PORT || 18080);
const JWT_SECRET = (process.env.JWT_SECRET || "change-me-in-production").trim();
const DATA_FILE = (process.env.DATA_FILE || "./data/data.json").trim();
const MEDIA_DIR = (process.env.MEDIA_DIR || "./media").trim();
const MEDIA_PUBLIC_BASE = (process.env.MEDIA_PUBLIC_BASE || "").trim();

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
    .replace(/[^a-z0-9_.]/g, "");
  return cleaned.slice(0, 24);
}

function genHandle(source) {
  const n = normalizeHandle(source);
  return n || `mora_${randHex(3)}`;
}

function canUseHandle(handle, uid) {
  const owner = db.handleIndex[handle];
  return !owner || owner === uid;
}

function allocateSystemHandle(uid, preferred) {
  const owner = String(uid || "").trim();
  const preferredNormalized = normalizeHandle(preferred);
  if (preferredNormalized && canUseHandle(preferredNormalized, owner)) return preferredNormalized;

  const idSeed = owner.replace(/[^a-z0-9]/gi, "").toLowerCase().slice(-8);
  if (idSeed) {
    const fromID = normalizeHandle(`mora_${idSeed}`);
    if (fromID && canUseHandle(fromID, owner)) return fromID;
  }

  for (let i = 0; i < 64; i += 1) {
    const randomHandle = normalizeHandle(`mora_${randHex(3)}`);
    if (randomHandle && canUseHandle(randomHandle, owner)) return randomHandle;
  }
  return `mora_${randHex(4)}`;
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

function emptyDB() {
  return { users: {}, emailIndex: {}, inviteIndex: {}, oauthIndex: {}, handleIndex: {}, likesIndex: {} };
}

async function ensureDirForFile(filePath) {
  await fsp.mkdir(path.dirname(filePath), { recursive: true });
}

async function loadDB() {
  try {
    const raw = await fsp.readFile(DATA_FILE, "utf8");
    if (!raw.trim()) return emptyDB();
    const parsed = JSON.parse(raw);
    return {
      users: parsed.users || {},
      emailIndex: parsed.emailIndex || {},
      inviteIndex: parsed.inviteIndex || {},
      oauthIndex: parsed.oauthIndex || {},
      handleIndex: parsed.handleIndex || {},
      likesIndex: parsed.likesIndex || {}
    };
  } catch (e) {
    if (e && e.code === "ENOENT") return emptyDB();
    throw e;
  }
}

let db = emptyDB();
let writeChain = Promise.resolve();

function saveDB() {
  writeChain = writeChain.then(async () => {
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

function isFriendOf(viewer, targetID) {
  return (viewer.friendIDs || []).includes(targetID);
}

function profileDTOForViewer(target, isSelf, isFriend) {
  const visibility = target.profileVisibility || visibilityFriendsOnly;
  const blocked = !isSelf && visibility === visibilityPrivate;
  const journeys = blocked ? [] : filterJourneys(target.journeys || [], isSelf, isFriend);
  const cards = blocked ? [] : (isSelf || isFriend ? (target.cityCards || []) : []);

  return {
    id: target.id,
    handle: target.handle ? `@${target.handle}` : null,
    inviteCode: target.inviteCode,
    profileVisibility: visibility,
    displayName: target.displayName,
    bio: target.bio,
    loadout: target.loadout,
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
  db.handleIndex = {};
  if (!db.likesIndex || typeof db.likesIndex !== "object") {
    db.likesIndex = {};
  }
  for (const [uid, user] of Object.entries(db.users || {})) {
    setUserHandle(uid, user.handle || user.displayName || uid, { strict: false });
    if (!user.profileVisibility) user.profileVisibility = visibilityFriendsOnly;
    ensureUserNotifications(user);
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
      setUserHandle(uid, email.split("@")[0], { strict: false });
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
      const key = `${provider}:${hashSHA256(idToken)}`;
      let uid = db.oauthIndex[key];
      if (!uid) {
        uid = `u_${randHex(12)}`;
        const invite = genInviteCode();
        db.users[uid] = {
          id: uid,
          provider,
          inviteCode: invite,
          handle: null,
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
        setUserHandle(uid, uid, { strict: false });
        db.oauthIndex[key] = uid;
        db.inviteIndex[invite] = uid;
        await saveDB();
      }
      const u = db.users[uid];
      return res.status(200).json({ userId: uid, provider: u.provider, email: u.email || null, accessToken: makeAccessToken(uid, u.provider), refreshToken: makeRefreshToken(uid, u.provider) });
    } catch {
      return res.status(500).json({ message: "internal error" });
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
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });
      const displayName = String(req.body?.displayName || "").trim();
      const handleRaw = String(req.body?.handle || "").trim();
      const inviteCodeRaw = req.body?.inviteCode == null ? "" : String(req.body.inviteCode).trim();
      if (!displayName && !inviteCodeRaw && !handleRaw) {
        return res.status(400).json({ message: "displayName or inviteCode or handle required" });
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
          return res.status(404).json({ message: "handle not found" });
        }
        return res.status(400).json({ message: "use inviteCode or handle to add friend" });
      }

      if (target.id === me.id) {
        return res.status(400).json({ message: "cannot add yourself" });
      }

      if ((me.friendIDs || []).includes(target.id)) {
        return res.status(200).json(friendDTOForViewer(target, true));
      }

      appendUnique(me.friendIDs, target.id);
      appendUnique(target.friendIDs, me.id);
      await saveDB();
      return res.status(200).json(friendDTOForViewer(target, true));
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

  app.patch("/v1/profile/handle", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });

      const incoming = String(req.body?.handle || "").trim();
      const updated = setUserHandle(uid, incoming, { strict: true });
      if (!updated.ok) {
        if (updated.code === "invalid_handle") {
          return res.status(400).json({ message: "invalid handle" });
        }
        if (updated.code === "handle_taken") {
          return res.status(409).json({ message: "handle already taken" });
        }
        return res.status(400).json({ message: "handle update failed" });
      }

      await saveDB();
      return res.status(200).json(profileDTOForViewer(me, true, true));
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

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
