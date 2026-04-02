const fs = require("fs");
const fsp = require("fs/promises");
const path = require("path");
const crypto = require("crypto");
const express = require("express");
const cors = require("cors");
const jwt = require("jsonwebtoken");
const multer = require("multer");
const compression = require("compression");
let Pool = null;
try {
  ({ Pool } = require("pg"));
} catch {
  Pool = null;
}
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const { OAuth2Client } = require("google-auth-library");
const { createRemoteJWKSet, jwtVerify } = require("jose");
const { canSendPostcard } = require("./postcard-rules");
const bcrypt = require("bcrypt");
const morgan = require("morgan");
const DB = require("./db-relational");
const APNs = require("./apns");

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
const PG_MAX_CLIENTS = Number(process.env.PG_MAX_CLIENTS || 20);
const JSON_BODY_LIMIT_MB = Number(process.env.JSON_BODY_LIMIT_MB || 3);
const MEDIA_UPLOAD_MAX_BYTES = Number(process.env.MEDIA_UPLOAD_MAX_BYTES || 10 * 1024 * 1024);
const CORS_ALLOWED_ORIGINS = String(process.env.CORS_ALLOWED_ORIGINS || "").trim();
const AUTH_RATE_LIMIT_WINDOW_MS = Number(process.env.AUTH_RATE_LIMIT_WINDOW_MS || 15 * 60 * 1000);
const AUTH_RATE_LIMIT_MAX = Number(process.env.AUTH_RATE_LIMIT_MAX || 20);
const AUTH_LOGIN_RATE_LIMIT_WINDOW_MS = Number(process.env.AUTH_LOGIN_RATE_LIMIT_WINDOW_MS || AUTH_RATE_LIMIT_WINDOW_MS);
const AUTH_LOGIN_RATE_LIMIT_MAX = Number(process.env.AUTH_LOGIN_RATE_LIMIT_MAX || AUTH_RATE_LIMIT_MAX);
const AUTH_REFRESH_RATE_LIMIT_WINDOW_MS = Number(process.env.AUTH_REFRESH_RATE_LIMIT_WINDOW_MS || 5 * 60 * 1000);
const AUTH_REFRESH_RATE_LIMIT_MAX = Number(process.env.AUTH_REFRESH_RATE_LIMIT_MAX || 80);
const WRITE_RATE_LIMIT_WINDOW_MS = Number(process.env.WRITE_RATE_LIMIT_WINDOW_MS || 60 * 1000);
const WRITE_RATE_LIMIT_MAX = Number(process.env.WRITE_RATE_LIMIT_MAX || 80);
const UPLOAD_RATE_LIMIT_WINDOW_MS = Number(process.env.UPLOAD_RATE_LIMIT_WINDOW_MS || 60 * 1000);
const UPLOAD_RATE_LIMIT_MAX = Number(process.env.UPLOAD_RATE_LIMIT_MAX || 30);
const TEST_EMAIL_OUTBOX_FILE = (process.env.TEST_EMAIL_OUTBOX_FILE || "").trim();
const AUTH_LINK_BASE = (process.env.AUTH_LINK_BASE || MEDIA_PUBLIC_BASE || "").trim();
const SES_FROM_EMAIL = (process.env.SES_FROM_EMAIL || "").trim();
const RESEND_API_KEY = (process.env.RESEND_API_KEY || "").trim();
const RESEND_FROM_EMAIL = (process.env.RESEND_FROM_EMAIL || "").trim();
const RESEND_API_BASE = (process.env.RESEND_API_BASE || "https://api.resend.com").trim().replace(/\/+$/, "");

const R2_ACCOUNT_ID = (process.env.R2_ACCOUNT_ID || "").trim();
const R2_ACCESS_KEY_ID = (process.env.R2_ACCESS_KEY_ID || "").trim();
const R2_SECRET_ACCESS_KEY = (process.env.R2_SECRET_ACCESS_KEY || "").trim();
const R2_BUCKET = (process.env.R2_BUCKET || "").trim();
const R2_ENDPOINT = (process.env.R2_ENDPOINT || (R2_ACCOUNT_ID ? `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com` : "")).trim();
const R2_REGION = (process.env.R2_REGION || "auto").trim();
const GOOGLE_CLIENT_ID = (process.env.GOOGLE_CLIENT_ID || "").trim();
const APPLE_AUDIENCES = (process.env.APPLE_AUDIENCES || process.env.APPLE_BUNDLE_ID || "").trim();
const APPSTORE_FALLBACK_URL = (process.env.APPSTORE_FALLBACK_URL || "https://apps.apple.com/us/search?term=StreetStamps").trim();
const WRITE_FREEZE_ENABLED = String(process.env.WRITE_FREEZE_ENABLED || "").trim().toLowerCase();
const SOCIAL_DISABLED_REGIONS = (process.env.SOCIAL_DISABLED_REGIONS || "CN").trim().toUpperCase().split(",").map(s => s.trim()).filter(Boolean);
const LEGACY_EMAIL_REVERIFY_EMAIL = normalizeEmail(process.env.LEGACY_EMAIL_REVERIFY_EMAIL || "yinterestingy@163.com");

const visibilityPrivate = "private";
const visibilityFriendsOnly = "friendsOnly";
const visibilityPublic = "public";
const allowedOrigins = CORS_ALLOWED_ORIGINS
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);
const NODE_ENV = String(process.env.NODE_ENV || "").trim().toLowerCase();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: Number.isFinite(MEDIA_UPLOAD_MAX_BYTES) && MEDIA_UPLOAD_MAX_BYTES > 0
      ? MEDIA_UPLOAD_MAX_BYTES
      : 10 * 1024 * 1024
  }
});
const rateLimitState = new Map();

function timingNowNs() {
  return process.hrtime.bigint();
}

function elapsedMs(startNs) {
  return Number((process.hrtime.bigint() - startNs) / 1000000n);
}

function logTiming(event, fields) {
  console.info(`[timing] ${JSON.stringify({ event, ...fields })}`);
}

const pgEnabled = Boolean(DATABASE_URL || (PGHOST && PGUSER && PGDATABASE));
let pgPool = null;
let pgSchemaReady = false;
if (pgEnabled) {
  if (!Pool) {
    throw new Error("pg module not installed but PostgreSQL config is enabled");
  }
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
const rawAppleFixtures = process.env.TEST_APPLE_OAUTH_FIXTURES || "{}";
let appleOAuthFixtures = {};
try {
  appleOAuthFixtures = JSON.parse(rawAppleFixtures);
} catch {
  appleOAuthFixtures = {};
}
function normalizeEmail(raw) {
  const email = String(raw || "").trim().toLowerCase();
  return email.includes("@") ? email : "";
}

function writeFreezeEnabled() {
  return WRITE_FREEZE_ENABLED === "1"
    || WRITE_FREEZE_ENABLED === "true"
    || WRITE_FREEZE_ENABLED === "yes";
}

function parseTruthy(raw) {
  if (typeof raw === "boolean") return raw;
  const value = String(raw || "").trim().toLowerCase();
  return value === "true" || value === "1";
}

function rejectWhenWriteFrozen(_req, res, next) {
  if (!writeFreezeEnabled()) return next();
  return res.status(503).json({
    code: "write_frozen",
    message: "service is temporarily read-only for migration"
  });
}

function corsConfigured() {
  return allowedOrigins.length > 0;
}

function originAllowed(origin) {
  if (!origin) return true;
  if (!corsConfigured()) return true;
  return allowedOrigins.includes(origin);
}

function applySecurityHeaders(res) {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Referrer-Policy", "same-origin");
  res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  res.setHeader("Cross-Origin-Resource-Policy", "cross-origin");
}

function applyHTMLSecurityHeaders(res) {
  applySecurityHeaders(res);
  res.setHeader("Content-Security-Policy", "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' https:;");
}

function makeRateLimiter({ keyPrefix, windowMs, maxHits, keyResolver }) {
  return function rateLimiter(req, res, next) {
    const now = Date.now();
    const safeWindow = Number.isFinite(windowMs) && windowMs > 0 ? windowMs : 60 * 1000;
    const safeMax = Number.isFinite(maxHits) && maxHits > 0 ? maxHits : 20;
    let resolvedKey = "";
    if (typeof keyResolver === "function") {
      try {
        resolvedKey = String(keyResolver(req) || "").trim();
      } catch {
        resolvedKey = "";
      }
    }
    if (!resolvedKey) {
      resolvedKey = req.ip || req.socket?.remoteAddress || "unknown";
    }
    const clientKey = `${keyPrefix}:${resolvedKey}`;
    const existing = rateLimitState.get(clientKey);
    if (!existing || existing.resetAt <= now) {
      rateLimitState.set(clientKey, { hits: 1, resetAt: now + safeWindow });
      return next();
    }
    existing.hits += 1;
    if (existing.hits > safeMax) {
      const retryAfterSeconds = Math.max(1, Math.ceil((existing.resetAt - now) / 1000));
      res.setHeader("Retry-After", String(retryAfterSeconds));
      return res.status(429).json({ message: "too many requests" });
    }
    return next();
  };
}

function refreshRateLimitKey(req) {
  const ip = req.ip || req.socket?.remoteAddress || "unknown";
  const refreshToken = String(req.body?.refreshToken || "").trim();
  if (!refreshToken) return `${ip}:no-token`;
  const fingerprint = crypto.createHash("sha256").update(refreshToken).digest("hex").slice(0, 16);
  return `${ip}:${fingerprint}`;
}

function weakJWTSecretConfigured() {
  if (!JWT_SECRET) return true;
  const normalized = JWT_SECRET.trim().toLowerCase();
  if (normalized === "change-me-in-production") return true;
  if (normalized === "change-me") return true;
  if (normalized === "replace-with-a-long-random-secret") return true;
  if (JWT_SECRET.length < 32) return true;
  return false;
}

function productionConfigError() {
  if (NODE_ENV !== "production") return "";
  if (weakJWTSecretConfigured()) {
    return "weak JWT_SECRET for production; set a high-entropy secret (>=32 chars)";
  }
  if (!corsConfigured()) {
    return "CORS_ALLOWED_ORIGINS must be configured in production";
  }
  return "";
}

function escapeHTML(raw) {
  return String(raw || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
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
  const fixture = appleOAuthFixtures[String(idToken || "").trim()];
  if (fixture && typeof fixture === "object") {
    const subject = String(fixture.sub || "").trim();
    if (!subject) throw new Error("invalid apple token subject");
    return {
      subject,
      email: normalizeEmail(fixture.email),
      emailVerified: parseTruthy(fixture.email_verified)
    };
  }
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

async function hashPassword(pw) {
  return bcrypt.hash(pw, 10);
}

async function verifyPassword(pw, hash) {
  try {
    return await bcrypt.compare(pw, hash);
  } catch {
    return false;
  }
}

function genInviteCode() {
  return randHex(4).toUpperCase();
}

function normalizeInviteCode(raw) {
  return String(raw || "").trim().toUpperCase();
}

function isStrongPassword(password) {
  const value = String(password || "");
  if (value.length < 8) return false;
  if (!/[A-Za-z]/.test(value)) return false;
  if (!/[0-9]/.test(value)) return false;
  if (!/[^A-Za-z0-9]/.test(value)) return false;
  return true;
}

function emailVerificationExpiresAt() {
  return nowUnix() + (24 * 60 * 60);
}

async function appendTestEmailOutbox(entry) {
  if (!TEST_EMAIL_OUTBOX_FILE) return;
  let items = [];
  try {
    const raw = await fsp.readFile(TEST_EMAIL_OUTBOX_FILE, "utf8");
    items = JSON.parse(raw);
    if (!Array.isArray(items)) items = [];
  } catch (error) {
    if (!error || error.code !== "ENOENT") throw error;
  }
  items.push(entry);
  await ensureDirForFile(TEST_EMAIL_OUTBOX_FILE);
  await fsp.writeFile(TEST_EMAIL_OUTBOX_FILE, JSON.stringify(items, null, 2), "utf8");
}

async function deliverEmailViaResend({ to, subject, text }) {
  if (!RESEND_API_KEY || !RESEND_FROM_EMAIL) return false;
  const response = await fetch(`${RESEND_API_BASE}/emails`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      from: RESEND_FROM_EMAIL,
      to: [to],
      subject,
      text
    })
  });
  if (!response.ok) {
    const raw = await response.text().catch(() => "");
    throw new Error(`resend send failed: ${response.status} ${raw}`.trim());
  }
  return true;
}

async function deliverEmailViaSES({ to, subject, text }) {
  if (!SES_FROM_EMAIL) {
    return false;
  }
  const { SESv2Client, SendEmailCommand } = require("@aws-sdk/client-sesv2");
  const client = new SESv2Client({});
  await client.send(new SendEmailCommand({
    FromEmailAddress: SES_FROM_EMAIL,
    Destination: { ToAddresses: [to] },
    Content: {
      Simple: {
        Subject: { Data: subject },
        Body: {
          Text: {
            Data: text
          }
        }
      }
    }
  }));
  return true;
}

async function deliverVerificationEmail(email, token) {
  const verificationURL = `${AUTH_LINK_BASE || "http://localhost"}/verify-email?token=${encodeURIComponent(token)}`;
  if (TEST_EMAIL_OUTBOX_FILE) {
    await appendTestEmailOutbox({
      kind: "verify_email",
      to: email,
      verificationURL
    });
    return;
  }
  const subject = "Verify your StreetStamps email";
  const text = `Verify your email by opening this link: ${verificationURL}`;
  if (await deliverEmailViaResend({ to: email, subject, text })) {
    return;
  }
  await deliverEmailViaSES({ to: email, subject, text });
}

async function deliverPasswordResetEmail(email, token) {
  const resetURL = `${AUTH_LINK_BASE || "http://localhost"}/reset-password?token=${encodeURIComponent(token)}`;
  if (TEST_EMAIL_OUTBOX_FILE) {
    await appendTestEmailOutbox({
      kind: "password_reset",
      to: email,
      resetURL
    });
    return;
  }
  const subject = "Reset your StreetStamps password";
  const text = `Reset your password by opening this link: ${resetURL}`;
  if (await deliverEmailViaResend({ to: email, subject, text })) {
    return;
  }
  await deliverEmailViaSES({ to: email, subject, text });
}

async function consumeEmailVerificationToken(rawToken) {
  const token = String(rawToken || "").trim();
  if (!token) return { ok: false, status: 400, message: "token required" };

  const tokenHash = hashSHA256(token);
  const tokenRecord = Object.values(db.emailVerificationTokens || {}).find((item) => item.tokenHash === tokenHash);
  if (!tokenRecord) return { ok: false, status: 400, message: "invalid token" };
  if (tokenRecord.usedAt) return { ok: false, status: 400, message: "token already used" };
  if (Number(tokenRecord.expiresAt || 0) < nowUnix()) return { ok: false, status: 400, message: "token expired" };

  const identity = Object.values(db.authIdentities || {}).find((item) => (
    item.provider === "email_password"
      && item.userID === tokenRecord.userID
      && item.email === tokenRecord.email
  ));
  if (!identity) return { ok: false, status: 400, message: "identity not found" };

  tokenRecord.usedAt = nowUnix();
  identity.emailVerified = true;
  identity.updatedAt = nowUnix();
  await persistPG(async () => {
    await DB.markEmailVerificationUsed(pgPool, tokenRecord.id, tokenRecord.usedAt);
    await DB.updateAuthIdentity(pgPool, identity.id, { emailVerified: true, updatedAt: identity.updatedAt });
  });
  return { ok: true, status: 200, email: tokenRecord.email };
}

function inspectPasswordResetToken(rawToken) {
  const token = String(rawToken || "").trim();
  if (!token) return { ok: false, status: 400, message: "token required" };

  const tokenHash = hashSHA256(token);
  const tokenRecord = Object.values(db.passwordResetTokens || {}).find((item) => item.tokenHash === tokenHash);
  if (!tokenRecord) return { ok: false, status: 400, message: "invalid token" };
  if (tokenRecord.usedAt) return { ok: false, status: 400, message: "token already used" };
  if (Number(tokenRecord.expiresAt || 0) < nowUnix()) return { ok: false, status: 400, message: "token expired" };
  return { ok: true, status: 200, token, tokenRecord };
}

function renderEmailVerificationHTML({ ok, title, body }) {
  const safeTitle = escapeHTML(title);
  const safeBody = escapeHTML(body);
  const accent = ok ? "#136f63" : "#9f2d2d";
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${safeTitle}</title>
  <style>
    :root { color-scheme: light; }
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: linear-gradient(180deg, #f7efe5 0%, #fffdf9 100%);
      color: #1f1f1f;
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 24px;
    }
    main {
      width: min(100%, 480px);
      background: rgba(255,255,255,0.96);
      border: 1px solid rgba(31,31,31,0.08);
      border-radius: 24px;
      padding: 28px 24px;
      box-shadow: 0 18px 50px rgba(31,31,31,0.08);
    }
    h1 {
      margin: 0 0 12px;
      font-size: 28px;
      line-height: 1.1;
      color: ${accent};
    }
    p {
      margin: 0 0 14px;
      font-size: 16px;
      line-height: 1.55;
    }
    .hint {
      color: #555;
      font-size: 14px;
    }
  </style>
</head>
<body>
  <main>
    <h1>${safeTitle}</h1>
    <p>${safeBody}</p>
    <p class="hint">Return to the StreetStamps app. If this link failed, request a new verification email and try again.</p>
  </main>
</body>
</html>`;
}

function renderPasswordResetHTML({ ok, title, body, deepLink = "" }) {
  const safeTitle = escapeHTML(title);
  const safeBody = escapeHTML(body);
  const safeDeepLink = escapeHTML(deepLink);
  const accent = ok ? "#136f63" : "#9f2d2d";
  const launchMarkup = ok ? `<p><a href="${safeDeepLink}">Open StreetStamps</a></p>` : "";
  const scriptMarkup = ok ? `<script>
    const target = ${JSON.stringify(deepLink)};
    window.setTimeout(() => { window.location.href = target; }, 120);
  </script>` : "";
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${safeTitle}</title>
  <style>
    :root { color-scheme: light; }
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: linear-gradient(180deg, #f7efe5 0%, #fffdf9 100%);
      color: #1f1f1f;
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 24px;
    }
    main {
      width: min(100%, 480px);
      background: rgba(255,255,255,0.96);
      border: 1px solid rgba(31,31,31,0.08);
      border-radius: 24px;
      padding: 28px 24px;
      box-shadow: 0 18px 50px rgba(31,31,31,0.08);
    }
    h1 {
      margin: 0 0 12px;
      font-size: 28px;
      line-height: 1.1;
      color: ${accent};
    }
    p {
      margin: 0 0 14px;
      font-size: 16px;
      line-height: 1.55;
    }
    a {
      color: #136f63;
      font-weight: 600;
      text-decoration: none;
    }
    .hint {
      color: #555;
      font-size: 14px;
    }
  </style>
</head>
<body>
  <main>
    <h1>${safeTitle}</h1>
    <p>${safeBody}</p>
    ${launchMarkup}
    <p class="hint">If the app does not open, return to StreetStamps and request another password reset email.</p>
  </main>
  ${scriptMarkup}
</body>
</html>`;
}

function revokeRefreshTokensForUser(userID) {
  const revokedAt = nowUnix();
  for (const record of Object.values(db.refreshTokens || {})) {
    if (record.userID === userID && !record.revokedAt) {
      record.revokedAt = revokedAt;
    }
  }
}

function findRefreshTokenRecord(rawToken) {
  const tokenHash = hashSHA256(String(rawToken || "").trim());
  return Object.values(db.refreshTokens || {}).find((item) => item.tokenHash === tokenHash) || null;
}

function isApplePrivateRelayEmail(email) {
  const normalized = normalizeEmail(email);
  return normalized.endsWith("@privaterelay.appleid.com");
}

function findAuthIdentityByProviderSubject(provider, providerSubject) {
  const normalizedProvider = String(provider || "").trim();
  const normalizedSubject = String(providerSubject || "").trim();
  if (!normalizedProvider || !normalizedSubject) return null;
  return Object.values(db.authIdentities || {}).find((item) => (
    item.provider === normalizedProvider && item.providerSubject === normalizedSubject
  )) || null;
}

function findVerifiedEmailPasswordIdentity(email) {
  const normalized = normalizeEmail(email);
  if (!normalized) return null;
  return Object.values(db.authIdentities || {}).find((item) => (
    item.provider === "email_password"
      && item.email === normalized
      && parseTruthy(item.emailVerified)
  )) || null;
}

function findEmailPasswordIdentity(email) {
  const normalized = normalizeEmail(email);
  if (!normalized) return null;
  return Object.values(db.authIdentities || {}).find((item) => (
    item.provider === "email_password"
      && item.email === normalized
  )) || null;
}

function userHasEmailPassword(userID) {
  if (!userID) return false;
  return Object.values(db.authIdentities || {}).some((item) => (
    item.provider === "email_password" && item.userID === userID
  ));
}

function canRecoverLegacyEmailRegistration(email) {
  const normalized = normalizeEmail(email);
  if (!normalized || normalized !== LEGACY_EMAIL_REVERIFY_EMAIL) return false;

  const indexedUserID = existingUserID(db.emailIndex?.[normalized]);
  if (!indexedUserID || !db.users?.[indexedUserID]) return false;

  const hasModernEmailIdentity = Object.values(db.authIdentities || {}).some((item) => (
    item.provider === "email_password"
      && item.email === normalized
  ));
  return !hasModernEmailIdentity;
}

function createDefaultUser(provider, email = "") {
  const uid = `u_${randHex(12)}`;
  const invite = genInviteCode();
  const user = {
    id: uid,
    provider,
    email: normalizeEmail(email) || null,
    inviteCode: invite,
    handle: null,
    handleChangeUsed: false,
    profileVisibility: visibilityFriendsOnly,
    displayName: "Explorer",
    profileSetupCompleted: false,
    bio: "Travel Enthusiastic",
    loadout: defaultLoadout(),
    journeys: [],
    cityCards: [],
    friendIDs: [],
    notifications: [],
    sentPostcards: [],
    receivedPostcards: [],
    createdAt: nowUnix()
  };
  db.users[uid] = user;
  setUserHandle(uid, null, { strict: false });
  db.inviteIndex[invite] = uid;
  return user;
}

function ensureUserInviteCode(uid, user) {
  const owner = existingUserID(uid);
  if (!owner || !user) return "";
  if (!db.inviteIndex || typeof db.inviteIndex !== "object") {
    db.inviteIndex = {};
  }

  let code = normalizeInviteCode(user.inviteCode);
  if (!code) {
    code = genInviteCode();
  } else {
    const indexedOwner = existingUserID(db.inviteIndex[code]);
    if (indexedOwner && indexedOwner !== owner) {
      const indexedUser = db.users[indexedOwner];
      if (normalizeInviteCode(indexedUser?.inviteCode) === code) {
        code = genInviteCode();
      }
    }
  }

  user.inviteCode = code;
  db.inviteIndex[code] = owner;
  return code;
}

function resolveUserByInviteCode(rawCode) {
  const code = normalizeInviteCode(rawCode);
  if (!code) return null;

  const indexedOwner = existingUserID(db.inviteIndex?.[code]);
  if (indexedOwner) {
    const indexedUser = db.users[indexedOwner];
    if (indexedUser && normalizeInviteCode(indexedUser.inviteCode) === code) {
      ensureUserInviteCode(indexedOwner, indexedUser);
      return indexedUser;
    }
  }

  for (const [uid, user] of Object.entries(db.users || {})) {
    if (normalizeInviteCode(user?.inviteCode) !== code) continue;
    ensureUserInviteCode(uid, user);
    return user;
  }

  return null;
}

function upsertAppleAuthIdentity(userID, subject, email, emailVerified) {
  const normalizedSubject = String(subject || "").trim();
  const normalizedEmail = normalizeEmail(email);
  let identity = findAuthIdentityByProviderSubject("apple", normalizedSubject);
  if (!identity) {
    const identityID = `aid_${randHex(12)}`;
    identity = {
      id: identityID,
      userID,
      provider: "apple",
      providerSubject: normalizedSubject,
      email: normalizedEmail || null,
      emailVerified: parseTruthy(emailVerified),
      passwordHash: null,
      createdAt: nowUnix(),
      updatedAt: nowUnix()
    };
    db.authIdentities[identityID] = identity;
    return identity;
  }
  identity.userID = userID;
  identity.email = normalizedEmail || identity.email || null;
  identity.emailVerified = parseTruthy(emailVerified) || parseTruthy(identity.emailVerified);
  identity.updatedAt = nowUnix();
  return identity;
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

function baseDisplayName(raw) {
  const trimmed = String(raw || "").trim();
  return trimmed || "Explorer";
}

function canUseDisplayName(displayName, excludedUserID = "") {
  const next = baseDisplayName(displayName);
  const owner = displayNameIndex.get(next);
  return !owner || owner === excludedUserID;
}


function normalizeHistoricalDisplayNames() {
  const users = Object.values(db.users || {})
    .filter(Boolean)
    .sort((left, right) => {
      const leftCreatedAt = Number(left?.createdAt || 0);
      const rightCreatedAt = Number(right?.createdAt || 0);
      if (leftCreatedAt !== rightCreatedAt) return leftCreatedAt - rightCreatedAt;
      return String(left?.id || "").localeCompare(String(right?.id || ""));
    });

  const used = new Set();
  let changed = false;

  for (const user of users) {
    const original = baseDisplayName(user.displayName);
    let next = original;
    if (used.has(next)) {
      let suffix = 2;
      while (used.has(`${original}${suffix}`)) {
        suffix += 1;
      }
      next = `${original}${suffix}`;
    }
    used.add(next);
    if (user.displayName !== next) {
      user.displayName = next;
      changed = true;
    }
    displayNameIndex.set(next, user.id);
  }

  return changed;
}

function ensureProfileSetupCompleted(user, defaultValue) {
  if (!user || typeof user !== "object") return false;
  if (typeof user.profileSetupCompleted === "boolean") return false;
  user.profileSetupCompleted = Boolean(defaultValue);
  return true;
}

function resolvedProfileSetupCompleted(user, defaultValue = true) {
  if (!user || typeof user !== "object") return Boolean(defaultValue);
  if (typeof user.profileSetupCompleted === "boolean") {
    return user.profileSetupCompleted;
  }
  return Boolean(defaultValue);
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
    const entry = { lat, lon };
    // Preserve GPS timestamp if present (ISO 8601 string or epoch seconds).
    if (item.t != null) {
      const parsed = typeof item.t === "string" ? new Date(item.t) : typeof item.t === "number" ? new Date(item.t * 1000) : null;
      if (parsed && !isNaN(parsed.getTime())) entry.t = parsed.toISOString();
    }
    out.push(entry);
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
    imageURLs: Array.isArray(m?.imageURLs) ? m.imageURLs.map((x) => String(x || "")).filter(Boolean).slice(0, 32) : [],
    latitude: typeof m?.latitude === "number" && Number.isFinite(m.latitude) ? m.latitude : null,
    longitude: typeof m?.longitude === "number" && Number.isFinite(m.longitude) ? m.longitude : null,
    locationStatus: ["resolved", "fallback", "pending"].includes(m?.locationStatus) ? m.locationStatus : null
  }));
}

function normalizeJourneyPayload(raw, ownerUserID) {
  return {
    id: String(raw?.id || `j_${randHex(8)}`),
    title: String(raw?.title || "Journey").slice(0, 120),
    cityID: String(raw?.cityID || raw?.cityId || "").trim() || null,
    activityTag: raw?.activityTag == null ? null : String(raw.activityTag).slice(0, 32),
    overallMemory: raw?.overallMemory == null ? null : String(raw.overallMemory).slice(0, 4000),
    overallMemoryImageURLs: Array.isArray(raw?.overallMemoryImageURLs)
      ? raw.overallMemoryImageURLs.map((x) => String(x || "")).filter(Boolean).slice(0, 32)
      : [],
    distance: Number(raw?.distance || 0),
    startTime: normalizeISOTime(raw?.startTime),
    endTime: normalizeISOTime(raw?.endTime),
    visibility: normalizeVisibility(raw?.visibility),
    sharedAt: normalizeISOTime(raw?.sharedAt),
    routeCoordinates: normalizeRouteCoordinates(raw?.routeCoordinates || raw?.coordinates),
    memories: normalizeJourneyMemories(raw?.memories),
    privacyOptions: Array.isArray(raw?.privacyOptions) ? raw.privacyOptions.filter(x => typeof x === "string").slice(0, 10) : undefined,
    ownerUserID: ownerUserID || undefined
  };
}

function normalizeCityCardPayload(raw) {
  const id = String(raw?.id || "").trim();
  if (!id) return null;
  return {
    id,
    name: String(raw?.name || id).trim() || id,
    countryISO2: raw?.countryISO2 == null ? null : String(raw.countryISO2 || "").trim() || null
  };
}

function mergeJourneyPayloads(existingJourneys, incomingJourneys, removedJourneyIDs, snapshotComplete, ownerUserID) {
  const normalizedIncoming = (incomingJourneys || []).map(j => normalizeJourneyPayload(j, ownerUserID));
  if (snapshotComplete) return normalizedIncoming;

  const removed = new Set((removedJourneyIDs || []).map((x) => String(x || "").trim()).filter(Boolean));
  const incomingByID = new Map(normalizedIncoming.map((journey) => [String(journey.id), journey]));
  const out = [...normalizedIncoming];

  for (const journey of existingJourneys || []) {
    const journeyID = String(journey?.id || "").trim();
    if (!journeyID || removed.has(journeyID) || incomingByID.has(journeyID)) continue;
    out.push(journey);
  }

  return out;
}

function mergeCityCardPayloads(existingCards, incomingCards, snapshotComplete) {
  const normalizedIncoming = (incomingCards || [])
    .map(normalizeCityCardPayload)
    .filter(Boolean);
  if (snapshotComplete) return normalizedIncoming;

  const incomingIDs = new Set(normalizedIncoming.map((card) => String(card.id)));
  const out = [...normalizedIncoming];

  for (const card of existingCards || []) {
    const cardID = String(card?.id || "").trim();
    if (!cardID || incomingIDs.has(cardID)) continue;
    out.push(card);
  }

  // Deduplicate final result by city ID
  const seen = new Map();
  const deduplicated = [];
  for (const card of out) {
    const id = String(card.id);
    if (!seen.has(id)) {
      seen.set(id, true);
      deduplicated.push(card);
    }
  }

  return deduplicated;
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

function resolveBearerUserID(token) {
  return parseLegacyAccessToken(token);
}

function defaultLoadout() {
  return {
    bodyId: "body",
    headId: "head",
    hairId: "hair_0001",
    suitId: null,
    upperId: "upper_0001",
    underId: "under_0001",
    savedUpperIdForSuit: "upper_0001",
    savedUnderIdForSuit: "under_0001",
    hatId: null,
    glassId: null,
    accessoryIds: [],
    expressionId: "expr_0001",
    hairColorHex: "#2B2A28",
    bodyColorHex: "#E8BE9C"
  };
}

function normalizeLoadout(raw, fallbackRaw) {
  const fallback = fallbackRaw ? normalizeLoadout(fallbackRaw) : defaultLoadout();
  const src = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};

  const firstString = (...values) => {
    for (const value of values) {
      if (typeof value === "string") {
        const trimmed = value.trim();
        if (trimmed) return trimmed;
      }
    }
    return "";
  };

  const normalizeLegacyHairId = (hairId) => {
    if (hairId === "hair_boy_default" || hairId === "hair_girl_default") return "hair_0001";
    return hairId;
  };

  const normalizeLegacyExpressionId = (expressionId) => {
    if (expressionId === "expr_default") return "expr_0001";
    return expressionId;
  };

  const legacyOutfitToUpper = {
    outfit_boy_suit: "upper_0001",
    outfit_girl_suit: "upper_0001"
  };
  const mapLegacyOutfit = (outfitId) => legacyOutfitToUpper[outfitId] || "";

  let accessoryIds = fallback.accessoryIds;
  if (Array.isArray(src.accessoryIds)) {
    accessoryIds = src.accessoryIds
      .map((item) => String(item || "").trim())
      .filter((item) => item && item !== "none");
  } else if (src.accessoryId === null) {
    accessoryIds = [];
  } else if (Object.prototype.hasOwnProperty.call(src, "accessoryId")) {
    const legacy = firstString(src.accessoryId);
    accessoryIds = legacy && legacy !== "none" ? [legacy] : [];
  }

  const upperFromLegacyOutfit = mapLegacyOutfit(firstString(src.outfitId));
  const hairId = normalizeLegacyHairId(
    firstString(src.hairId, fallback.hairId, "hair_0001")
  );
  const expressionId = normalizeLegacyExpressionId(
    firstString(src.expressionId, fallback.expressionId, "expr_0001")
  );
  const upperId = firstString(src.upperId, upperFromLegacyOutfit, fallback.upperId, "upper_0001");
  const underId = firstString(src.underId, fallback.underId, "under_0001");
  const savedUpperIdForSuit = firstString(src.savedUpperIdForSuit, upperId, fallback.savedUpperIdForSuit, "upper_0001");
  const savedUnderIdForSuit = firstString(src.savedUnderIdForSuit, underId, fallback.savedUnderIdForSuit, "under_0001");
  const suitId = src.suitId == null ? null : firstString(src.suitId);
  const hatId = src.hatId == null ? null : firstString(src.hatId);
  const glassId = src.glassId == null ? null : firstString(src.glassId);

  return {
    bodyId: firstString(src.bodyId, fallback.bodyId, "body"),
    headId: firstString(src.headId, fallback.headId, "head"),
    hairId,
    suitId,
    upperId,
    underId,
    savedUpperIdForSuit,
    savedUnderIdForSuit,
    hatId,
    glassId,
    accessoryIds,
    expressionId,
    hairColorHex: firstString(src.hairColorHex, fallback.hairColorHex, "#2B2A28"),
    bodyColorHex: firstString(src.bodyColorHex, fallback.bodyColorHex, "#E8BE9C")
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

function makeAccessToken(uid, provider) {
  return jwt.sign({ uid, prv: provider, typ: "access", sid: randHex(8) }, JWT_SECRET, { expiresIn: "7d" });
}

function makeRefreshToken(uid, provider) {
  return jwt.sign({ uid, prv: provider, typ: "refresh", sid: randHex(8) }, JWT_SECRET, { expiresIn: "30d" });
}

function extractBearerToken(req) {
  const h = req.headers.authorization || "";
  if (!h.startsWith("Bearer ")) throw new Error("missing bearer");
  return h.slice(7).trim();
}

function parseLegacyAccessToken(token) {
  const payload = jwt.verify(token, JWT_SECRET);
  if (!payload || payload.typ !== "access") throw new Error("invalid token");
  return payload.uid;
}

function parseBearer(req) {
  const token = extractBearerToken(req);
  if (req.authError) throw req.authError;
  if (req.authUserID) return req.authUserID;
  return parseLegacyAccessToken(token);
}

function parseRefreshToken(rawToken) {
  const tok = String(rawToken || "").trim();
  if (!tok) throw new Error("missing refresh token");
  const payload = jwt.verify(tok, JWT_SECRET);
  if (!payload || payload.typ !== "refresh") throw new Error("invalid refresh token");
  return payload;
}

function emptyDB() {
  return {
    users: {},
    emailIndex: {},
    inviteIndex: {},
    oauthIndex: {},
    authIdentities: {},
    emailVerificationTokens: {},
    passwordResetTokens: {},
    refreshTokens: {},
    handleIndex: {},
    likesIndex: {},
    friendRequestsIndex: {},
    postcardsIndex: {}
  };
}

function normalizeDBShape(parsed) {
  return {
    users: parsed?.users || {},
    emailIndex: parsed?.emailIndex || {},
    inviteIndex: parsed?.inviteIndex || {},
    oauthIndex: parsed?.oauthIndex || {},
    authIdentities: parsed?.authIdentities || {},
    emailVerificationTokens: parsed?.emailVerificationTokens || {},
    passwordResetTokens: parsed?.passwordResetTokens || {},
    refreshTokens: parsed?.refreshTokens || {},
    handleIndex: parsed?.handleIndex || {},
    likesIndex: parsed?.likesIndex || {},
    friendRequestsIndex: parsed?.friendRequestsIndex || {},
    postcardsIndex: parsed?.postcardsIndex || {}
  };
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
  // Create relational tables
  await DB.ensureSchema(pgPool);
  // Keep legacy app_state table for migration fallback
  await pgPool.query(`
    CREATE TABLE IF NOT EXISTS app_state (
      key TEXT PRIMARY KEY,
      state JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  pgSchemaReady = true;
}

async function saveDBToPostgres(nextDB) {
  if (!pgPool) return;
  await ensurePGSchema();
  // Fast JSON blob fallback — relational tables are written by targeted persistPG/persistPGTx calls.
  await pgPool.query(
    `INSERT INTO app_state (key, state) VALUES ('global', $1)
     ON CONFLICT (key) DO UPDATE SET state = $1`,
    [JSON.stringify(nextDB)]
  );
}

async function loadDB() {
  if (!pgPool) return loadDBFromFile();

  // PG mode: only ensure schema, do NOT load all data into memory.
  // All route handlers now query PG directly.
  await ensurePGSchema();
  console.log("[db] PG-direct mode — skipping full memory load");
  return emptyDB();
}

let db = emptyDB();
let writeChain = Promise.resolve();
let writeLock = false;
const displayNameIndex = new Map();

function saveDB() {
  writeChain = writeChain.then(async () => {
    while (writeLock) {
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    writeLock = true;
    try {
      if (pgPool) {
        await saveDBToPostgres(db);
        return;
      }
      await ensureDirForFile(DATA_FILE);
      await fsp.writeFile(DATA_FILE, JSON.stringify(db, null, 2), "utf8");
    } finally {
      writeLock = false;
    }
  });
  return writeChain;
}

// ---------------------------------------------------------------------------
// Targeted incremental persistence helpers
// ---------------------------------------------------------------------------

async function persistPG(pgAction) {
  if (pgPool) {
    await pgAction();
  } else {
    await saveDB();
  }
}

async function persistPGTx(pgAction) {
  if (!pgPool) { await saveDB(); return; }
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await pgAction(client);
    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
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
      likedAtByUserID: {},
      updatedAt: new Date().toISOString()
    };
  }
  if (!Array.isArray(db.likesIndex[key].likerIDs)) db.likesIndex[key].likerIDs = [];
  if (!db.likesIndex[key].likedAtByUserID || typeof db.likesIndex[key].likedAtByUserID !== "object") {
    db.likesIndex[key].likedAtByUserID = {};
  }
  return db.likesIndex[key];
}

function ensureUserNotifications(user) {
  if (!Array.isArray(user.notifications)) user.notifications = [];
}

function ensurePostcardCollections(user) {
  if (!Array.isArray(user.sentPostcards)) user.sentPostcards = [];
  if (!Array.isArray(user.receivedPostcards)) user.receivedPostcards = [];
}

function ensurePostcardIndex() {
  if (!db.postcardsIndex || typeof db.postcardsIndex !== "object") {
    db.postcardsIndex = {};
  }
}

function oauthSubjectKey(provider, subject) {
  const normalizedProvider = String(provider || "").trim().toLowerCase();
  const normalizedSubject = String(subject || "").trim();
  if (!normalizedProvider || !normalizedSubject) return "";
  return `${normalizedProvider}:${normalizedSubject}`;
}

function oauthLegacyKey(provider, idToken) {
  const normalizedProvider = String(provider || "").trim().toLowerCase();
  const normalizedToken = String(idToken || "").trim();
  if (!normalizedProvider || !normalizedToken) return "";
  return `${normalizedProvider}:${hashSHA256(normalizedToken)}`;
}

function existingUserID(rawUID) {
  const uid = String(rawUID || "").trim();
  if (!uid) return "";
  return db.users[uid] ? uid : "";
}

async function existingUserIDAsync(rawUID) {
  const uid = String(rawUID || "").trim();
  if (!uid) return "";
  if (!pgPool) return existingUserID(rawUID);
  return (await DB.getUserExists(pgPool, uid)) ? uid : "";
}

// ---------------------------------------------------------------------------
// Async PG-aware data access layer
// When pgPool is available, reads go to PG. Otherwise fallback to in-memory db.
// ---------------------------------------------------------------------------

async function getUser(uid) {
  if (!pgPool) return db.users[uid] || null;
  return DB.getUserByID(pgPool, uid);
}

async function getUserJourneys(uid) {
  if (!pgPool) return (db.users[uid]?.journeys) || [];
  return DB.getJourneysByUser(pgPool, uid);
}

async function getUserFriendIDs(uid) {
  if (!pgPool) return (db.users[uid]?.friendIDs) || [];
  return DB.getFriendIDs(pgPool, uid);
}

async function checkAreFriends(uid1, uid2) {
  if (!pgPool) {
    const u = db.users[uid1];
    return u ? (u.friendIDs || []).includes(uid2) : false;
  }
  return DB.areFriends(pgPool, uid1, uid2);
}

async function getUserNotifications(uid) {
  if (!pgPool) {
    const u = db.users[uid];
    return u?.notifications || [];
  }
  return DB.getNotifications(pgPool, uid);
}

async function getUserByEmailAsync(email) {
  if (!pgPool) {
    const uid = db.emailIndex[email];
    return uid ? (db.users[uid] || null) : null;
  }
  return DB.getUserByEmail(pgPool, email);
}

async function getUserByHandleAsync(handle) {
  if (!pgPool) {
    const uid = db.handleIndex[handle];
    return uid ? (db.users[uid] || null) : null;
  }
  return DB.getUserByHandle(pgPool, handle);
}

async function findAuthIdentityByProviderSubjectAsync(provider, providerSubject) {
  if (!pgPool) return findAuthIdentityByProviderSubject(provider, providerSubject);
  return DB.findAuthIdentityByProviderSubject(pgPool, provider, providerSubject);
}

async function findEmailPasswordIdentityAsync(email) {
  if (!pgPool) return findEmailPasswordIdentity(email);
  return DB.findEmailPasswordIdentity(pgPool, email);
}

async function findVerifiedEmailPasswordIdentityAsync(email) {
  if (!pgPool) return findVerifiedEmailPasswordIdentity(email);
  return DB.findVerifiedEmailPasswordIdentity(pgPool, email);
}

async function userHasEmailPasswordAsync(userID) {
  if (!pgPool) return userHasEmailPassword(userID);
  const identities = await DB.findAuthIdentitiesByUserID(pgPool, userID);
  return identities.some((item) => item.provider === "email_password");
}

async function findRefreshTokenRecordAsync(rawToken) {
  if (!pgPool) return findRefreshTokenRecord(rawToken);
  const tokenHash = hashSHA256(String(rawToken || "").trim());
  return DB.findRefreshTokenByHash(pgPool, tokenHash);
}

async function getOAuthUserAsync(key) {
  if (!pgPool) return db.oauthIndex[key] || null;
  return DB.getOAuthUser(pgPool, key);
}

async function resolveUserByAnyIDAsync(rawID) {
  const candidate = String(rawID || "").trim();
  if (!candidate) return null;
  if (!pgPool) return resolveUserByAnyID(rawID);
  let user = await DB.getUserByID(pgPool, candidate);
  if (user) return user;
  if (candidate.startsWith("account_")) {
    user = await DB.getUserByID(pgPool, candidate.slice("account_".length));
    if (user) return user;
  } else {
    user = await DB.getUserByID(pgPool, `account_${candidate}`);
    if (user) return user;
  }
  return null;
}

async function resolveUserByInviteCodeAsync(rawCode) {
  const code = normalizeInviteCode(rawCode);
  if (!code) return null;
  if (!pgPool) return resolveUserByInviteCode(rawCode);
  return DB.getUserByInviteCode(pgPool, code);
}

async function canUseDisplayNameAsync(displayName, excludedUserID = "") {
  if (!pgPool) return canUseDisplayName(displayName, excludedUserID);
  const exists = await DB.displayNameExists(pgPool, displayName, excludedUserID);
  return !exists;
}

async function isSafeEmptyOAuthAccountAsync(uid) {
  if (!pgPool) return isSafeEmptyOAuthAccount(uid);
  const user = await DB.getUserByID(pgPool, uid);
  if (!user) return false;
  if (user.provider !== "google" && user.provider !== "apple") return false;
  return DB.isEmptyAccount(pgPool, uid);
}

async function profileDTOForViewerAsync(target, isSelf, isFriend) {
  const visibility = target.profileVisibility || visibilityFriendsOnly;
  const blocked = !isSelf && visibility === visibilityPrivate;

  let journeys, cards;
  if (pgPool) {
    journeys = blocked ? [] : await DB.getJourneysByUser(pgPool, target.id);
    cards = blocked ? [] : await DB.getCityCardsByUser(pgPool, target.id);
  } else {
    journeys = blocked ? [] : (target.journeys || []);
    cards = blocked ? [] : (target.cityCards || []);
  }

  journeys = filterJourneys(journeys, isSelf, isFriend);
  if (!isSelf && !isFriend) cards = [];

  if (!isSelf && cards.length > 0 && journeys.length > 0) {
    const visibleCityIDs = new Set();
    for (const j of journeys) {
      const ck = (j.cityID || j.startCityKey || j.cityKey || "").trim();
      if (ck) visibleCityIDs.add(ck);
    }
    cards = cards.filter((c) => visibleCityIDs.has((c.id || "").trim()));
  } else if (!isSelf) {
    cards = [];
  }

  const hasEmailPwd = isSelf ? await userHasEmailPasswordAsync(target.id) : undefined;

  return {
    id: target.id,
    handle: target.handle || null,
    exclusiveID: target.handle || null,
    inviteCode: target.inviteCode,
    profileVisibility: visibility,
    displayName: target.displayName,
    profileSetupCompleted: resolvedProfileSetupCompleted(target, true),
    email: isSelf ? (target.email || null) : null,
    bio: target.bio,
    loadout: normalizeLoadout(target.loadout),
    handleChangeUsed: Boolean(target.handleChangeUsed),
    canUpdateHandleOneTime: !target.handleChangeUsed,
    hasEmailPassword: hasEmailPwd,
    stats: isSelf ? profileStatsFrom(target) : {
      totalJourneys: journeys.length,
      totalDistance: journeys.reduce((acc, j) => acc + Number(j.distance || 0), 0),
      totalMemories: journeys.reduce((acc, j) => acc + ((j.memories || []).length), 0),
      totalUnlockedCities: cards.length
    },
    journeys,
    unlockedCityCards: cards
  };
}

async function friendDTOForViewerAsync(u, isFriend) {
  return profileDTOForViewerAsync(u, false, isFriend);
}

async function friendRequestDTOAsync(request) {
  const from = pgPool ? await DB.getUserByID(pgPool, request.fromUserID) : db.users[request.fromUserID];
  const to = pgPool ? await DB.getUserByID(pgPool, request.toUserID) : db.users[request.toUserID];
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

async function isBlockedEitherDirectionSafe(userA, userB) {
  if (!pgPool) return false; // blocking not supported in file mode
  return DB.isBlockedEitherDirection(pgPool, userA, userB);
}

async function canViewJourneyAsync(viewerID, ownerID, journey) {
  if (viewerID === ownerID) return true;
  const isFriend = await checkAreFriends(viewerID, ownerID);
  const v = normalizeVisibility(journey?.visibility);
  if (v === visibilityPublic) return true;
  if (v === visibilityFriendsOnly && isFriend) return true;
  return false;
}

// Notification helpers that write directly to PG (no in-memory mutation needed in PG mode)
async function insertNotificationDirect(ownerID, notification) {
  if (pgPool) {
    await DB.insertNotification(pgPool, {
      id: notification.id,
      userID: ownerID,
      type: notification.type || "unknown",
      fromUserID: notification.fromUserID || null,
      fromDisplayName: notification.fromDisplayName || null,
      journeyID: notification.journeyID || null,
      journeyTitle: notification.journeyTitle || null,
      message: notification.message || "",
      read: notification.read ?? false,
      createdAt: notification.createdAt || new Date().toISOString(),
    });
  } else {
    const user = db.users[ownerID];
    if (user) {
      ensureUserNotifications(user);
      user.notifications.unshift(notification);
      if (user.notifications.length > 400) user.notifications = user.notifications.slice(0, 400);
    }
  }
}

async function pushNotificationAndPersist(ownerID, notification, pushAlert, pushData) {
  await insertNotificationDirect(ownerID, notification);
  fireRemotePush(ownerID, pushAlert, pushData);
}

async function postcardReactionPayloadForViewerAsync(viewerID, item, box) {
  const messageID = String(item?.messageID || "").trim();
  if (!messageID) return { reaction: null, myReaction: null, peerReaction: null };

  if (pgPool) {
    let myReaction = null;
    let peerReaction = null;
    if (box === "received") {
      myReaction = await DB.getPostcardReaction(pgPool, messageID, viewerID);
    } else {
      const receiverID = item.toUserID;
      if (receiverID) peerReaction = await DB.getPostcardReaction(pgPool, messageID, receiverID);
    }
    return {
      reaction: box === "received" ? myReaction : peerReaction,
      myReaction,
      peerReaction
    };
  }
  return postcardReactionPayloadForViewer(viewerID, item, box);
}

// Issue tokens and persist directly to PG (no in-memory storage in PG mode)
async function issueEmailVerificationTokenAsync(userID, email) {
  const rawToken = randHex(24);
  const tokenID = `evt_${randHex(12)}`;
  const tokenData = {
    id: tokenID,
    userID,
    email,
    tokenHash: hashSHA256(rawToken),
    expiresAt: emailVerificationExpiresAt(),
    usedAt: null,
    createdAt: nowUnix()
  };
  if (pgPool) {
    await DB.insertEmailVerificationToken(pgPool, tokenData);
  } else {
    db.emailVerificationTokens[tokenID] = tokenData;
  }
  return rawToken;
}

async function issuePasswordResetTokenAsync(userID, email) {
  const rawToken = randHex(24);
  const tokenID = `prt_${randHex(12)}`;
  const tokenData = {
    id: tokenID,
    userID,
    email,
    tokenHash: hashSHA256(rawToken),
    expiresAt: emailVerificationExpiresAt(),
    usedAt: null,
    createdAt: nowUnix()
  };
  if (pgPool) {
    await DB.insertPasswordResetToken(pgPool, tokenData);
  } else {
    db.passwordResetTokens[tokenID] = tokenData;
  }
  return rawToken;
}

async function issueStoredRefreshTokenAsync(userID, provider, deviceInfo = null) {
  const rawToken = makeRefreshToken(userID, provider);
  const tokenID = `rft_${randHex(12)}`;
  const tokenData = {
    id: tokenID,
    userID,
    tokenHash: hashSHA256(rawToken),
    deviceInfo: deviceInfo || null,
    expiresAt: nowUnix() + (30 * 24 * 60 * 60),
    revokedAt: null,
    createdAt: nowUnix()
  };
  if (pgPool) {
    await DB.insertRefreshToken(pgPool, tokenData);
  } else {
    db.refreshTokens[tokenID] = tokenData;
  }
  return rawToken;
}

async function consumeEmailVerificationTokenAsync(rawToken) {
  const token = String(rawToken || "").trim();
  if (!token) return { ok: false, status: 400, message: "token required" };
  if (!pgPool) return consumeEmailVerificationToken(rawToken);

  const tokenHash = hashSHA256(token);
  const tokenRecord = await DB.findEmailVerificationByHash(pgPool, tokenHash);
  if (!tokenRecord) return { ok: false, status: 400, message: "invalid token" };
  if (tokenRecord.usedAt) return { ok: false, status: 400, message: "token already used" };
  if (Number(tokenRecord.expiresAt || 0) < nowUnix()) return { ok: false, status: 400, message: "token expired" };

  const identities = await DB.findAuthIdentitiesByUserID(pgPool, tokenRecord.userID);
  const identity = identities.find((item) =>
    item.provider === "email_password" && item.email === tokenRecord.email
  );
  if (!identity) return { ok: false, status: 400, message: "identity not found" };

  const usedAt = nowUnix();
  await DB.markEmailVerificationUsed(pgPool, tokenRecord.id, usedAt);
  await DB.updateAuthIdentity(pgPool, identity.id, { emailVerified: true, updatedAt: nowUnix() });
  return { ok: true, status: 200, email: tokenRecord.email };
}

async function inspectPasswordResetTokenAsync(rawToken) {
  const token = String(rawToken || "").trim();
  if (!token) return { ok: false, status: 400, message: "token required" };
  if (!pgPool) return inspectPasswordResetToken(rawToken);

  const tokenHash = hashSHA256(token);
  const tokenRecord = await DB.findPasswordResetByHash(pgPool, tokenHash);
  if (!tokenRecord) return { ok: false, status: 400, message: "invalid token" };
  if (tokenRecord.usedAt) return { ok: false, status: 400, message: "token already used" };
  if (Number(tokenRecord.expiresAt || 0) < nowUnix()) return { ok: false, status: 400, message: "token expired" };
  return { ok: true, status: 200, token, tokenRecord };
}

async function authSuccessPayloadAsync(user, provider, email, accessToken, refreshToken) {
  return {
    userId: user.id,
    provider,
    email: email || null,
    accessToken,
    refreshToken,
    needsProfileSetup: !resolvedProfileSetupCompleted(user, true),
    hasEmailPassword: await userHasEmailPasswordAsync(user.id)
  };
}

async function setUserHandleAsync(uid, rawHandle, options = { strict: false }) {
  if (!pgPool) return setUserHandle(uid, rawHandle, options);
  const user = await DB.getUserByID(pgPool, uid);
  if (!user) return { ok: false, code: "user_not_found" };

  let next = "";
  if (options.strict) {
    next = normalizeHandle(rawHandle);
    if (!next) return { ok: false, code: "invalid_handle" };
    if (await DB.handleExists(pgPool, next, uid)) return { ok: false, code: "handle_taken" };
  } else {
    // For auto-assign, try preferred, then random
    const preferred = normalizeHandle(rawHandle);
    if (preferred && !(await DB.handleExists(pgPool, preferred, uid))) {
      next = preferred;
    } else {
      for (let i = 0; i < 500; i++) {
        const numeric = genAutoNumericHandle();
        if (!(await DB.handleExists(pgPool, numeric, uid))) { next = numeric; break; }
      }
      if (!next) next = `${nowUnix()}${Math.floor(Math.random() * 10)}`.slice(-8);
    }
  }

  await DB.updateUser(pgPool, uid, { handle: next });
  return { ok: true, handle: next };
}

async function createDefaultUserAsync(provider, email = "") {
  if (!pgPool) return createDefaultUser(provider, email);
  const uid = `u_${randHex(12)}`;
  const invite = genInviteCode();
  const user = {
    id: uid,
    provider,
    email: normalizeEmail(email) || null,
    inviteCode: invite,
    handle: null,
    handleChangeUsed: false,
    profileVisibility: visibilityFriendsOnly,
    displayName: "Explorer",
    profileSetupCompleted: false,
    bio: "Travel Enthusiastic",
    loadout: defaultLoadout(),
    createdAt: nowUnix()
  };
  await DB.insertUser(pgPool, user);
  const handleResult = await setUserHandleAsync(uid, null, { strict: false });
  user.handle = handleResult.handle || user.handle;
  return user;
}

async function oauthCandidateScoreAsync(uid, source) {
  if (!(await existingUserIDAsync(uid))) return -1;
  const sourceBase = source === "modern" ? 3 : source === "legacy" ? 2 : 1;
  return sourceBase + (await isSafeEmptyOAuthAccountAsync(uid) ? 0 : 100);
}

async function chooseCanonicalOAuthUserIDAsync(candidates) {
  if (!pgPool) return chooseCanonicalOAuthUserID(candidates);
  const seen = new Set();
  let bestUID = "";
  let bestScore = -1;
  for (const candidate of candidates) {
    const uid = await existingUserIDAsync(candidate?.uid);
    if (!uid || seen.has(uid)) continue;
    seen.add(uid);
    const score = await oauthCandidateScoreAsync(uid, candidate?.source);
    if (score > bestScore) {
      bestUID = uid;
      bestScore = score;
    }
  }
  return bestUID;
}

async function mergeEmptyOAuthAccountIntoAsync(sourceUID, targetUID) {
  if (!pgPool) return mergeEmptyOAuthAccountInto(sourceUID, targetUID);
  const fromUID = await existingUserIDAsync(sourceUID);
  const toUID = await existingUserIDAsync(targetUID);
  if (!fromUID || !toUID || fromUID === toUID) return false;
  if (!(await isSafeEmptyOAuthAccountAsync(fromUID))) return false;

  const source = await DB.getUserByID(pgPool, fromUID);
  const target = await DB.getUserByID(pgPool, toUID);
  if (!source || !target) return false;

  if (!target.email && source.email) {
    await DB.updateUser(pgPool, toUID, { email: source.email });
  }
  // Reassign oauth/email indexes pointing to source → target
  await DB.transferOAuthEntries(pgPool, fromUID, toUID);
  await DB.deleteUserByID(pgPool, fromUID);
  return true;
}

async function upsertAppleAuthIdentityAsync(userID, subject, email, emailVerified) {
  if (!pgPool) return upsertAppleAuthIdentity(userID, subject, email, emailVerified);
  const normalizedSubject = String(subject || "").trim();
  const normalizedEmail = normalizeEmail(email);
  const identity = await findAuthIdentityByProviderSubjectAsync("apple", normalizedSubject);
  if (!identity) {
    const identityID = `aid_${randHex(12)}`;
    const newIdentity = {
      id: identityID,
      userID,
      provider: "apple",
      providerSubject: normalizedSubject,
      email: normalizedEmail || null,
      emailVerified: parseTruthy(emailVerified),
      passwordHash: null,
      createdAt: nowUnix(),
      updatedAt: nowUnix()
    };
    await DB.insertAuthIdentity(pgPool, newIdentity);
    return newIdentity;
  }
  const updatedAt = nowUnix();
  const updates = {
    userID,
    email: normalizedEmail || identity.email || null,
    emailVerified: parseTruthy(emailVerified) || parseTruthy(identity.emailVerified),
    updatedAt
  };
  await DB.updateAuthIdentity(pgPool, identity.id, updates);
  return { ...identity, ...updates };
}

function hasUserLikesOrLikeOwnership(uid) {
  for (const record of Object.values(db.likesIndex || {})) {
    if (!record) continue;
    if (record.ownerUserID === uid) return true;
    if (Array.isArray(record.likerIDs) && record.likerIDs.includes(uid)) return true;
  }
  return false;
}

function hasUserFriendLinks(uid) {
  for (const user of Object.values(db.users || {})) {
    if (!user || !Array.isArray(user.friendIDs)) continue;
    if (user.friendIDs.includes(uid)) return true;
  }
  return false;
}

function hasUserFriendRequests(uid) {
  return allFriendRequests().some((item) => item.fromUserID === uid || item.toUserID === uid);
}

function hasUserPostcards(uid) {
  for (const item of Object.values(db.postcardsIndex || {})) {
    if (!item) continue;
    if (item.fromUserID === uid || item.toUserID === uid) return true;
  }
  return false;
}

function isSafeEmptyOAuthAccount(uid) {
  const user = db.users[uid];
  if (!user) return false;
  if (user.provider !== "google" && user.provider !== "apple") return false;
  if (user.passwordHash) return false;
  if (Array.isArray(user.journeys) && user.journeys.length > 0) return false;
  if (Array.isArray(user.cityCards) && user.cityCards.length > 0) return false;
  if (Array.isArray(user.friendIDs) && user.friendIDs.length > 0) return false;
  if (Array.isArray(user.notifications) && user.notifications.length > 0) return false;
  if (Array.isArray(user.sentPostcards) && user.sentPostcards.length > 0) return false;
  if (Array.isArray(user.receivedPostcards) && user.receivedPostcards.length > 0) return false;
  if (hasUserLikesOrLikeOwnership(uid)) return false;
  if (hasUserFriendLinks(uid)) return false;
  if (hasUserFriendRequests(uid)) return false;
  if (hasUserPostcards(uid)) return false;
  return true;
}

function oauthCandidateScore(uid, source) {
  if (!existingUserID(uid)) return -1;
  const sourceBase = source === "modern" ? 3 : source === "legacy" ? 2 : 1;
  return sourceBase + (isSafeEmptyOAuthAccount(uid) ? 0 : 100);
}

function chooseCanonicalOAuthUserID(candidates) {
  const seen = new Set();
  let bestUID = "";
  let bestScore = -1;

  for (const candidate of candidates) {
    const uid = existingUserID(candidate?.uid);
    if (!uid || seen.has(uid)) continue;
    seen.add(uid);
    const score = oauthCandidateScore(uid, candidate?.source);
    if (score > bestScore) {
      bestUID = uid;
      bestScore = score;
    }
  }
  return bestUID;
}

function mergeEmptyOAuthAccountInto(sourceUID, targetUID) {
  const fromUID = existingUserID(sourceUID);
  const toUID = existingUserID(targetUID);
  if (!fromUID || !toUID || fromUID === toUID) return false;
  if (!isSafeEmptyOAuthAccount(fromUID)) return false;

  const source = db.users[fromUID];
  const target = db.users[toUID];
  if (!source || !target) return false;

  if (!target.email && source.email) {
    target.email = source.email;
  }

  for (const [email, ownerUID] of Object.entries(db.emailIndex || {})) {
    if (ownerUID === fromUID) db.emailIndex[email] = toUID;
  }
  for (const [key, ownerUID] of Object.entries(db.oauthIndex || {})) {
    if (ownerUID === fromUID) db.oauthIndex[key] = toUID;
  }
  for (const [handle, ownerUID] of Object.entries(db.handleIndex || {})) {
    if (ownerUID === fromUID) delete db.handleIndex[handle];
  }
  for (const [inviteCode, ownerUID] of Object.entries(db.inviteIndex || {})) {
    if (ownerUID === fromUID) delete db.inviteIndex[inviteCode];
  }

  delete db.users[fromUID];
  return true;
}

function derivePublicBase(req) {
  const xfProto = String(req?.headers?.["x-forwarded-proto"] || "").split(",")[0].trim();
  const xfHost = String(req?.headers?.["x-forwarded-host"] || "").split(",")[0].trim();
  const host = xfHost || String(req?.headers?.host || "").split(",")[0].trim();
  const proto = xfProto || req?.protocol || "";
  if (host && proto) return `${proto}://${host}`.replace(/\/$/, "");
  if (MEDIA_PUBLIC_BASE) return MEDIA_PUBLIC_BASE.replace(/\/$/, "");
  return "";
}

function absolutizePostcardPhotoURL(rawURL, req) {
  const value = String(rawURL || "").trim();
  if (!value) return "";
  if (/^https?:\/\//i.test(value)) return value;
  if (!value.startsWith("/")) return value;
  const base = derivePublicBase(req);
  if (!base) return value;
  return `${base}${value}`;
}

function normalizePostcardMessage(raw) {
  if (!raw || typeof raw !== "object") return null;
  const messageID = String(raw.messageID || "").trim();
  const fromUserID = String(raw.fromUserID || "").trim();
  const toUserID = String(raw.toUserID || "").trim();
  if (!messageID || !fromUserID || !toUserID) return null;

  return {
    messageID,
    type: "postcard",
    fromUserID,
    fromDisplayName: raw.fromDisplayName == null ? null : String(raw.fromDisplayName),
    toUserID,
    toDisplayName: raw.toDisplayName == null ? null : String(raw.toDisplayName),
    cityID: String(raw.cityID || "").trim(),
    cityName: String(raw.cityName || raw.cityID || "").trim(),
    photoURL: raw.photoURL == null ? null : String(raw.photoURL),
    messageText: String(raw.messageText || "").slice(0, 2000),
    sentAt: normalizeISOTime(raw.sentAt) || new Date().toISOString(),
    clientDraftID: String(raw.clientDraftID || "").trim(),
    status: raw.status == null ? "sent" : String(raw.status)
  };
}

function upsertPostcard(raw) {
  const normalized = normalizePostcardMessage(raw);
  if (!normalized) return null;
  ensurePostcardIndex();
  db.postcardsIndex[normalized.messageID] = normalized;
  return normalized;
}

function postcardsForUser(uid, box) {
  ensurePostcardIndex();
  const out = Object.values(db.postcardsIndex || {}).filter((item) => {
    if (!item || typeof item !== "object") return false;
    if (box === "received") return item.toUserID === uid;
    return item.fromUserID === uid;
  });
  out.sort((a, b) => Date.parse(b.sentAt || "") - Date.parse(a.sentAt || ""));
  return out;
}

function postcardReactionPayloadForViewer(viewerID, item, box) {
  const viewer = db.users?.[viewerID];
  const sender = db.users?.[item?.fromUserID];
  const receiver = db.users?.[item?.toUserID];
  const messageID = String(item?.messageID || "").trim();
  if (!messageID) {
    return {
      reaction: null,
      myReaction: null,
      peerReaction: null
    };
  }

  let myReaction = null;
  let peerReaction = null;

  if (box === "received") {
    // Reactions made by the receiver are stored on the sender record.
    myReaction = sender?.postcardReactions?.[messageID] || null;
  } else {
    // Reactions made by the receiver of my sent postcard are stored on my record.
    peerReaction = viewer?.postcardReactions?.[messageID] || null;
  }

  // Keep a defensive peer lookup so legacy data still renders if the payload is stored on the
  // opposite side unexpectedly.
  if (!peerReaction && box === "received") {
    peerReaction = receiver?.postcardReactions?.[messageID] || null;
  }
  if (!myReaction && box === "sent") {
    myReaction = viewer?.postcardReactions?.[messageID] || null;
  }

  return {
    reaction: box === "received" ? myReaction : peerReaction,
    myReaction,
    peerReaction
  };
}

function reconcilePostcardsForUser(user, uid) {
  ensurePostcardCollections(user);
  const expectedSent = postcardsForUser(uid, "sent");
  const expectedReceived = postcardsForUser(uid, "received");

  const currentSentIDs = (user.sentPostcards || []).map((x) => String(x?.messageID || ""));
  const currentReceivedIDs = (user.receivedPostcards || []).map((x) => String(x?.messageID || ""));
  const nextSentIDs = expectedSent.map((x) => x.messageID);
  const nextReceivedIDs = expectedReceived.map((x) => x.messageID);

  let changed = false;
  if (JSON.stringify(currentSentIDs) !== JSON.stringify(nextSentIDs)) {
    user.sentPostcards = expectedSent;
    changed = true;
  }
  if (JSON.stringify(currentReceivedIDs) !== JSON.stringify(nextReceivedIDs)) {
    user.receivedPostcards = expectedReceived;
    changed = true;
  }
  return changed;
}

/**
 * Fire an APNs remote push to a user (non-blocking, best-effort).
 * @param {string} ownerID - target user ID
 * @param {{ title: string, body: string }} alert
 * @param {object} [data] - optional custom data payload
 */
function fireRemotePush(ownerID, alert, data) {
  if (!APNs.isConfigured() || !pgPool) return;
  // Run async in background — never block the HTTP response
  (async () => {
    try {
      const tokens = await DB.getPushTokens(pgPool, ownerID);
      if (!tokens.length) return;
      await APNs.sendToUser(tokens, alert, data, async (invalidToken) => {
        await DB.deletePushToken(pgPool, ownerID, invalidToken);
      });
    } catch (err) {
      console.error(`[APNs] fireRemotePush error for ${ownerID}:`, err.message);
    }
  })();
}

function isFriendOf(viewer, targetID) {
  return (viewer.friendIDs || []).includes(targetID);
}

function resolveUserByAnyID(rawID) {
  const candidate = String(rawID || "").trim();
  if (!candidate) return null;
  if (db.users[candidate]) return db.users[candidate];
  if (candidate.startsWith("account_")) {
    const stripped = candidate.slice("account_".length);
    if (db.users[stripped]) return db.users[stripped];
  } else {
    const prefixed = `account_${candidate}`;
    if (db.users[prefixed]) return db.users[prefixed];
  }
  return null;
}

function friendRequestUserDTO(user) {
  return {
    id: user.id,
    displayName: user.displayName,
    handle: user.handle || null,
    exclusiveID: user.handle || null,
    loadout: normalizeLoadout(user.loadout)
  };
}

function allFriendRequests() {
  return Object.values(db.friendRequestsIndex || {}).filter((x) => x && x.id && x.fromUserID && x.toUserID);
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

function collectFriendRequestIDsBetween(userA, userB) {
  const ids = [];
  for (const req of allFriendRequests()) {
    const sameDirection = req.fromUserID === userA && req.toUserID === userB;
    const reverseDirection = req.fromUserID === userB && req.toUserID === userA;
    if (sameDirection || reverseDirection) ids.push(req.id);
  }
  return ids;
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

async function main() {
  const prodConfigError = productionConfigError();
  if (prodConfigError) {
    throw new Error(prodConfigError);
  }
  db = await loadDB();
  console.log(`[streetstamps-node-v1] storage=${pgPool ? "postgresql-direct" : "file"}`);

  if (!pgPool) {
    // In-memory mode: run post-load migrations on the loaded data
    db.handleIndex = {};
    db.inviteIndex = {};
    let shouldPersistMigration = false;
    if (!db.likesIndex || typeof db.likesIndex !== "object") {
      db.likesIndex = {};
    }
    if (!db.friendRequestsIndex || typeof db.friendRequestsIndex !== "object") {
      db.friendRequestsIndex = {};
    }
    ensurePostcardIndex();
    for (const [uid, user] of Object.entries(db.users || {})) {
      setUserHandle(uid, user.handle || user.displayName || uid, { strict: false });
      ensureUserInviteCode(uid, user);
      if (!user.profileVisibility) user.profileVisibility = visibilityFriendsOnly;
      if (typeof user.handleChangeUsed !== "boolean") {
        user.handleChangeUsed = false;
      }
      shouldPersistMigration = ensureProfileSetupCompleted(user, true) || shouldPersistMigration;
      user.loadout = normalizeLoadout(user.loadout);
      ensureUserNotifications(user);
      ensurePostcardCollections(user);
      for (const item of user.sentPostcards) upsertPostcard(item);
      for (const item of user.receivedPostcards) upsertPostcard(item);
    }
    for (const [uid, user] of Object.entries(db.users || {})) {
      reconcilePostcardsForUser(user, uid);
    }
    shouldPersistMigration = normalizeHistoricalDisplayNames() || shouldPersistMigration;
    for (const req of allFriendRequests()) {
      const from = db.users[req.fromUserID];
      const to = db.users[req.toUserID];
      if (!from || !to || from.id === to.id || isFriendOf(from, to.id)) {
        delete db.friendRequestsIndex[req.id];
      }
    }
    if (shouldPersistMigration) {
      await saveDB();
    }
  }
  await fsp.mkdir(MEDIA_DIR, { recursive: true });

  const app = express();
  app.set("trust proxy", true);
  app.disable("x-powered-by");
  app.use((req, res, next) => {
    applySecurityHeaders(res);
    const origin = String(req.headers.origin || "").trim();
    if (!originAllowed(origin)) {
      return res.status(403).json({ message: "origin not allowed" });
    }
    if (origin) {
      res.setHeader("Access-Control-Allow-Origin", origin);
      res.setHeader("Vary", "Origin");
      res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
      res.setHeader("Access-Control-Allow-Methods", "GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS");
      res.setHeader("Access-Control-Allow-Credentials", "true");
    } else if (!corsConfigured()) {
      res.setHeader("Access-Control-Allow-Origin", "*");
    }
    if (req.method === "OPTIONS") {
      return res.status(204).end();
    }
    return next();
  });
  app.use(compression());
  app.use(morgan(":remote-addr :method :url :status :res[content-length] - :response-time ms"));
  app.use(express.json({
    limit: `${Number.isFinite(JSON_BODY_LIMIT_MB) && JSON_BODY_LIMIT_MB > 0 ? JSON_BODY_LIMIT_MB : 6}mb`
  }));
  app.use("/media", express.static(MEDIA_DIR, { maxAge: "30d", immutable: true }));
  app.use((req, _res, next) => {
    const header = String(req.headers.authorization || "");
    if (!header.startsWith("Bearer ")) {
      return next();
    }
    try {
      req.authUserID = resolveBearerUserID(header.slice(7).trim());
    } catch (error) {
      req.authError = error;
    }
    return next();
  });
  const authRateLimiter = makeRateLimiter({
    keyPrefix: "auth-general",
    windowMs: AUTH_RATE_LIMIT_WINDOW_MS,
    maxHits: AUTH_RATE_LIMIT_MAX
  });
  const authLoginRateLimiter = makeRateLimiter({
    keyPrefix: "auth-login",
    windowMs: AUTH_LOGIN_RATE_LIMIT_WINDOW_MS,
    maxHits: AUTH_LOGIN_RATE_LIMIT_MAX
  });
  const authRefreshRateLimiter = makeRateLimiter({
    keyPrefix: "auth-refresh",
    windowMs: AUTH_REFRESH_RATE_LIMIT_WINDOW_MS,
    maxHits: AUTH_REFRESH_RATE_LIMIT_MAX,
    keyResolver: refreshRateLimitKey
  });
  const writeRateLimiter = makeRateLimiter({
    keyPrefix: "write",
    windowMs: WRITE_RATE_LIMIT_WINDOW_MS,
    maxHits: WRITE_RATE_LIMIT_MAX
  });
  const uploadRateLimiter = makeRateLimiter({
    keyPrefix: "upload",
    windowMs: UPLOAD_RATE_LIMIT_WINDOW_MS,
    maxHits: UPLOAD_RATE_LIMIT_MAX
  });
  const readRateLimiter = makeRateLimiter({
    keyPrefix: "read",
    windowMs: WRITE_RATE_LIMIT_WINDOW_MS,
    maxHits: 120
  });
  const profileWriteRateLimiter = makeRateLimiter({
    keyPrefix: "profile-write",
    windowMs: 60000,
    maxHits: 15
  });
  const profileReadRateLimiter = makeRateLimiter({
    keyPrefix: "profile-read",
    windowMs: 60000,
    maxHits: 60
  });

  app.get("/open/invite", (req, res) => {
    applyHTMLSecurityHeaders(res);
    const inviteCode = String(req.query?.code || "").trim().toUpperCase();
    const handle = String(req.query?.handle || "").trim().replace(/^@+/, "");

    if (!inviteCode && !handle) {
      return res.status(400).send("missing invite code or handle");
    }

    const params = new URLSearchParams();
    if (inviteCode) params.set("code", inviteCode);
    if (handle) params.set("handle", handle);
    const appURL = `streetstamps://add-friend?${params.toString()}`;

    const safeAppURL = JSON.stringify(appURL);
    const safeFallbackURL = JSON.stringify(APPSTORE_FALLBACK_URL);
    const safeInviteCode = escapeHTML(inviteCode ? inviteCode : "");
    const safeHandle = escapeHTML(handle ? `@${handle}` : "");

    return res
      .status(200)
      .type("html")
      .send(`<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>StreetStamps 邀请</title>
  <style>
    body{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC","Helvetica Neue",Arial,sans-serif;background:#f5f6fb;margin:0;padding:0}
    .card{max-width:520px;margin:36px auto;padding:24px;background:#fff;border-radius:18px;box-shadow:0 10px 28px rgba(0,0,0,.08)}
    h1{margin:0 0 10px;font-size:28px}
    p{margin:6px 0;color:#424242;line-height:1.6}
    .meta{margin-top:14px;padding:12px;border-radius:12px;background:#f7f8fb}
    .btn{display:inline-block;margin-top:16px;padding:12px 18px;border-radius:12px;text-decoration:none;font-weight:700}
    .btn-open{background:#1f8f45;color:#fff}
    .btn-store{margin-left:10px;background:#eceff5;color:#111}
  </style>
</head>
<body>
  <div class="card">
    <h1>StreetStamps 好友邀请</h1>
    <p>正在打开 App 并跳转到“加好友”页面。</p>
    <div class="meta">
      <p>邀请码：${safeInviteCode || "（未提供）"}</p>
      <p>专属ID：${safeHandle || "（未提供）"}</p>
    </div>
    <a class="btn btn-open" href="${appURL}">立即打开 App</a>
    <a class="btn btn-store" href="${APPSTORE_FALLBACK_URL}">没有 App？去下载</a>
  </div>
  <script>
    (function() {
      var appURL = ${safeAppURL};
      var fallbackURL = ${safeFallbackURL};
      var redirected = false;
      function toStore() {
        if (redirected) return;
        redirected = true;
        window.location.replace(fallbackURL);
      }
      var timer = setTimeout(toStore, 1500);
      window.location.href = appURL;
      document.addEventListener("visibilitychange", function() {
        if (document.hidden) clearTimeout(timer);
      });
    })();
  </script>
</body>
</html>`);
  });

  app.get("/v1/health", (_req, res) => res.status(200).json({
    status: "ok",
    storage: pgPool ? "postgresql" : "file",
    cors: corsConfigured() ? "allowlist" : "open",
    auth: {
      businessBearer: "backend_jwt_only"
    },
    maintenance: {
      writeFrozen: writeFreezeEnabled()
    },
    media: {
      maxUploadBytes: Number.isFinite(MEDIA_UPLOAD_MAX_BYTES) && MEDIA_UPLOAD_MAX_BYTES > 0
        ? MEDIA_UPLOAD_MAX_BYTES
        : 10 * 1024 * 1024,
      objectStorage: Boolean(r2Client)
    }
  }));

  app.get("/v1/feature-flags", (req, res) => {
    const region = String(req.query.region || req.headers["x-storefront-region"] || "").trim().toUpperCase();
    const socialEnabled = region ? !SOCIAL_DISABLED_REGIONS.includes(region) : true;
    res.status(200).json({
      social: socialEnabled,
      region: region || null
    });
  });

  app.post("/v1/auth/register", authRateLimiter, async (req, res) => {
    try {
      const email = String(req.body?.email || "").trim().toLowerCase();
      const password = String(req.body?.password || "");
      const displayName = String(req.body?.displayName || "").trim();
      if (!email.includes("@")) return res.status(400).json({ message: "invalid email" });
      if (!isStrongPassword(password)) {
        return res.status(400).json({ message: "password must be at least 8 characters and include a letter, number, and special character" });
      }
      const existingEmailIdentity = await findEmailPasswordIdentityAsync(email);
      const existingEmailUser = pgPool
        ? await DB.getUserByEmail(pgPool, email)
        : (db.emailIndex[email] ? db.users[db.emailIndex[email]] : null);
      const canRecover = !existingEmailUser || (pgPool
        ? !(existingEmailIdentity)
        : canRecoverLegacyEmailRegistration(email));

      if (existingEmailUser && !canRecover) {
        if (existingEmailIdentity && !parseTruthy(existingEmailIdentity.emailVerified)) {
          const existingUser = await getUser(existingEmailIdentity.userID);
          if (!existingUser) return res.status(409).json({ message: "email already exists" });

          const now = nowUnix();
          const passwordHash = await hashPassword(password);
          let updatedDisplayName = existingUser.displayName;
          if (displayName) {
            const normalized = normalizeDisplayName(displayName);
            if (normalized && await canUseDisplayNameAsync(normalized, existingEmailIdentity.userID)) {
              updatedDisplayName = normalized;
            }
          }
          if (!pgPool) {
            existingEmailIdentity.passwordHash = passwordHash;
            existingEmailIdentity.updatedAt = now;
            existingUser.passwordHash = passwordHash;
            existingUser.displayName = updatedDisplayName;
          }
          const verificationToken = await issueEmailVerificationTokenAsync(existingEmailIdentity.userID, email);
          await persistPG(async () => {
            await DB.updateAuthIdentity(pgPool, existingEmailIdentity.id, { passwordHash, updatedAt: now });
            await DB.updateUser(pgPool, existingEmailIdentity.userID, { displayName: updatedDisplayName });
          });
          await deliverVerificationEmail(email, verificationToken);

          return res.status(200).json({
            userId: existingEmailIdentity.userID,
            email,
            emailVerificationRequired: true,
            needsProfileSetup: !resolvedProfileSetupCompleted(existingUser, true)
          });
        }
        return res.status(409).json({ message: "email already exists" });
      }

      const uid = `u_${randHex(12)}`;
      const invite = genInviteCode();
      const passwordHash = await hashPassword(password);
      const createdAt = nowUnix();
      const user = {
        id: uid,
        provider: "email",
        email,
        passwordHash,
        inviteCode: invite,
        handle: null,
        handleChangeUsed: false,
        profileVisibility: visibilityFriendsOnly,
        displayName: displayName || "Explorer",
        profileSetupCompleted: false,
        bio: "Travel Enthusiastic",
        loadout: defaultLoadout(),
        journeys: [],
        cityCards: [],
        friendIDs: [],
        notifications: [],
        sentPostcards: [],
        receivedPostcards: [],
        createdAt
      };
      if (!pgPool) {
        db.users[uid] = user;
        db.emailIndex[email] = uid;
        db.inviteIndex[invite] = uid;
      }
      const identityID = `aid_${randHex(12)}`;
      const identityObj = {
        id: identityID,
        userID: uid,
        provider: "email_password",
        providerSubject: email,
        email,
        emailVerified: false,
        passwordHash,
        createdAt,
        updatedAt: createdAt
      };
      if (!pgPool) {
        db.authIdentities[identityID] = identityObj;
      }
      await persistPG(async () => {
        await DB.insertUser(pgPool, user);
        await DB.insertAuthIdentity(pgPool, identityObj);
      });
      const handleResult = await setUserHandleAsync(uid, null, { strict: false });
      user.handle = handleResult.handle || user.handle;
      const verificationToken = await issueEmailVerificationTokenAsync(uid, email);
      await deliverVerificationEmail(email, verificationToken);

      return res.status(200).json({
        userId: uid,
        email,
        emailVerificationRequired: true,
        needsProfileSetup: true
      });
    } catch (err) {
      console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.post("/v1/auth/verify-email", authRateLimiter, async (req, res) => {
    try {
      const result = await consumeEmailVerificationTokenAsync(req.body?.token);
      if (!result.ok) return res.status(result.status).json({ message: result.message });
      return res.status(200).json({ ok: true, email: result.email });
    } catch (err) {
      console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.get("/verify-email", async (req, res) => {
    try {
      applyHTMLSecurityHeaders(res);
      const result = await consumeEmailVerificationTokenAsync(req.query?.token);
      if (!result.ok) {
        res.status(result.status);
        res.type("html");
        return res.send(renderEmailVerificationHTML({
          ok: false,
          title: "Verification link failed",
          body: result.message === "token expired"
            ? "This verification link has expired."
            : "This verification link is invalid or has already been used."
        }));
      }
      res.status(200);
      res.type("html");
      return res.send(renderEmailVerificationHTML({
        ok: true,
        title: "Email verified",
        body: "Your StreetStamps email has been verified. You can return to the app and sign in."
      }));
    } catch (err) {
      console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      res.status(500);
      res.type("html");
      return res.send(renderEmailVerificationHTML({
        ok: false,
        title: "Verification link failed",
        body: "We could not verify your email right now."
      }));
    }
  });

  app.get("/reset-password", async (req, res) => {
    try {
      applyHTMLSecurityHeaders(res);
      const result = await inspectPasswordResetTokenAsync(req.query?.token);
      if (!result.ok) {
        res.status(result.status);
        res.type("html");
        return res.send(renderPasswordResetHTML({
          ok: false,
          title: "Reset link failed",
          body: result.message === "token expired"
            ? "This password reset link has expired."
            : "This password reset link is invalid or has already been used."
        }));
      }
      const deepLink = `streetstamps://reset-password?token=${encodeURIComponent(result.token)}`;
      res.status(200);
      res.type("html");
      return res.send(renderPasswordResetHTML({
        ok: true,
        title: "Open StreetStamps",
        body: "Continue in the StreetStamps app to choose a new password.",
        deepLink
      }));
    } catch (err) {
      console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      res.status(500);
      res.type("html");
      return res.send(renderPasswordResetHTML({
        ok: false,
        title: "Reset link failed",
        body: "We could not open the password reset flow right now."
      }));
    }
  });

  app.post("/v1/auth/resend-verification", authRateLimiter, async (req, res) => {
    try {
      const email = normalizeEmail(req.body?.email);
      if (!email) return res.status(200).json({ ok: true });

      const identity = await findEmailPasswordIdentityAsync(email);
      if (!identity || parseTruthy(identity.emailVerified)) {
        return res.status(200).json({ ok: true });
      }

      const token = await issueEmailVerificationTokenAsync(identity.userID, email);
      await deliverVerificationEmail(email, token);
      return res.status(200).json({ ok: true });
    } catch (err) {
      console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.post("/v1/auth/login", authLoginRateLimiter, async (req, res) => {
    try {
      const email = String(req.body?.email || "").trim().toLowerCase();
      const password = String(req.body?.password || "");
      const identity = await findEmailPasswordIdentityAsync(email);
      if (!identity) return res.status(404).json({ message: "account not found" });

      // 验证密码（支持旧SHA256和新bcrypt）
      let passwordValid = false;
      if (identity.passwordHash.startsWith("$2")) {
        // bcrypt格式
        passwordValid = await verifyPassword(password, identity.passwordHash);
      } else {
        // 旧SHA256格式，自动升级
        const oldHash = hashSHA256(`StreetStamps::${password}`);
        if (identity.passwordHash === oldHash) {
          passwordValid = true;
          // 升级到bcrypt
          const newHash = await hashPassword(password);
          const updatedAt = nowUnix();
          if (!pgPool) { identity.passwordHash = newHash; identity.updatedAt = updatedAt; }
          await persistPG(async () => {
            await DB.updateAuthIdentity(pgPool, identity.id, { passwordHash: newHash, updatedAt });
          });
        }
      }

      if (!passwordValid) return res.status(401).json({ message: "wrong email or password" });
      if (!identity.emailVerified) return res.status(403).json({ message: "email not verified" });

      const user = await getUser(identity.userID);
      if (!user) return res.status(404).json({ message: "account not found" });

      const accessToken = makeAccessToken(user.id, user.provider || "email");
      const refreshToken = await issueStoredRefreshTokenAsync(user.id, user.provider || "email");
      return res.status(200).json(await authSuccessPayloadAsync(
        user,
        user.provider || "email",
        user.email || identity.email || null,
        accessToken,
        refreshToken
      ));
    } catch (err) {
      console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.post("/v1/auth/refresh", authRefreshRateLimiter, async (req, res) => {
    try {
      const rawToken = String(req.body?.refreshToken || "").trim();
      const payload = parseRefreshToken(rawToken);
      const record = await findRefreshTokenRecordAsync(rawToken);
      if (!record || record.revokedAt) return res.status(401).json({ message: "refresh token invalid" });
      if (Number(record.expiresAt || 0) < nowUnix()) return res.status(401).json({ message: "refresh token expired" });

      const user = await getUser(payload.uid);
      if (!user) return res.status(401).json({ message: "account not found" });

      return res.status(200).json({
        accessToken: makeAccessToken(user.id, user.provider || payload.prv || "email")
      });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "refresh token invalid" });
    }
  });

  app.post("/v1/auth/logout", authRateLimiter, async (req, res) => {
    try {
      const rawToken = String(req.body?.refreshToken || "").trim();
      if (!rawToken) return res.status(400).json({ message: "refresh token required" });
      parseRefreshToken(rawToken);
      const record = await findRefreshTokenRecordAsync(rawToken);
      if (!record) return res.status(401).json({ message: "refresh token invalid" });
      if (!record.revokedAt) {
        if (!pgPool) record.revokedAt = nowUnix();
        await persistPG(async () => {
          await DB.revokeRefreshToken(pgPool, record.id);
        });
      }
      return res.status(200).json({ ok: true });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "refresh token invalid" });
    }
  });

  app.post("/v1/auth/forgot-password", authRateLimiter, async (req, res) => {
    try {
      const email = String(req.body?.email || "").trim().toLowerCase();
      if (!email.includes("@")) {
        return res.status(200).json({ ok: true });
      }
      const identity = await findEmailPasswordIdentityAsync(email);
      if (identity) {
        const token = await issuePasswordResetTokenAsync(identity.userID, email);
        await deliverPasswordResetEmail(email, token);
      }
      return res.status(200).json({ ok: true });
    } catch (err) {
      console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.post("/v1/auth/reset-password", authRateLimiter, async (req, res) => {
    try {
      const rawToken = String(req.body?.token || "").trim();
      const newPassword = String(req.body?.newPassword || "");
      if (!rawToken) return res.status(400).json({ message: "token required" });
      if (!isStrongPassword(newPassword)) {
        return res.status(400).json({ message: "password must be at least 8 characters and include a letter, number, and special character" });
      }

      const inspectResult = await inspectPasswordResetTokenAsync(rawToken);
      if (!inspectResult.ok) return res.status(inspectResult.status).json({ message: inspectResult.message });
      const tokenRecord = inspectResult.tokenRecord;

      // Find the identity for this password reset
      let identity;
      if (pgPool) {
        const identities = await DB.findAuthIdentitiesByUserID(pgPool, tokenRecord.userID);
        identity = identities.find((item) =>
          item.provider === "email_password" && item.email === tokenRecord.email
        );
      } else {
        identity = Object.values(db.authIdentities || {}).find((item) => (
          item.provider === "email_password"
            && item.userID === tokenRecord.userID
            && item.email === tokenRecord.email
        ));
      }
      if (!identity) return res.status(400).json({ message: "identity not found" });

      const nextHash = await hashPassword(newPassword);
      const updatedAt = nowUnix();
      const usedAt = nowUnix();
      if (!pgPool) {
        identity.passwordHash = nextHash;
        identity.updatedAt = updatedAt;
        const user = db.users[tokenRecord.userID];
        if (user) user.passwordHash = nextHash;
        tokenRecord.usedAt = usedAt;
        revokeRefreshTokensForUser(tokenRecord.userID);
      }
      await persistPG(async () => {
        await DB.updateAuthIdentity(pgPool, identity.id, { passwordHash: nextHash, updatedAt });
        await DB.markPasswordResetUsed(pgPool, tokenRecord.id, usedAt);
        await DB.revokeRefreshTokensForUser(pgPool, tokenRecord.userID);
      });
      return res.status(200).json({ ok: true });
    } catch (err) {
      console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.post("/v1/auth/apple", authLoginRateLimiter, async (req, res) => {
    try {
      const idToken = String(req.body?.idToken || "").trim();
      if (!idToken) return res.status(400).json({ message: "idToken required" });

      const identity = await verifyAppleIdentity(idToken);
      const modernKey = oauthSubjectKey("apple", identity.subject);
      const legacyKey = oauthLegacyKey("apple", idToken);
      const existingAppleIdentity = await findAuthIdentityByProviderSubjectAsync("apple", identity.subject);
      const relayEmail = isApplePrivateRelayEmail(identity.email);
      const verifiedEmailIdentity = identity.email && identity.emailVerified && !relayEmail
        ? await findVerifiedEmailPasswordIdentityAsync(identity.email)
        : null;

      const modernOAuthUID = await getOAuthUserAsync(modernKey);
      const legacyOAuthUID = await getOAuthUserAsync(legacyKey);
      const modernUID = await existingUserIDAsync(existingAppleIdentity?.userID || modernOAuthUID);
      const legacyUID = await existingUserIDAsync(legacyOAuthUID);
      const emailUID = await existingUserIDAsync(verifiedEmailIdentity?.userID);

      let uid = await chooseCanonicalOAuthUserIDAsync([
        { uid: modernUID, source: "modern" },
        { uid: legacyUID, source: "legacy" },
        { uid: emailUID, source: "email" }
      ]);

      if (modernUID && modernUID !== uid) await mergeEmptyOAuthAccountIntoAsync(modernUID, uid);
      if (legacyUID && legacyUID !== uid) await mergeEmptyOAuthAccountIntoAsync(legacyUID, uid);
      if (emailUID && emailUID !== uid) await mergeEmptyOAuthAccountIntoAsync(emailUID, uid);

      if (!uid) {
        const newUser = await createDefaultUserAsync("apple", identity.email);
        uid = newUser.id;
      }

      if (!uid) return res.status(500).json({ message: "user not found after apple login" });

      let user = await getUser(uid);
      if (!user) return res.status(500).json({ message: "user not found after apple login" });

      if (modernKey) {
        if (pgPool) {
          await DB.setOAuthUser(pgPool, modernKey, uid);
        } else if (db.oauthIndex[modernKey] !== uid) {
          db.oauthIndex[modernKey] = uid;
        }
      }

      let emailToUpdate = null;
      if (!relayEmail && identity.email && identity.emailVerified) {
        const currentEmailUser = await getUserByEmailAsync(identity.email);
        const currentEmailUID = currentEmailUser?.id || "";
        if (!user.email && (!currentEmailUID || currentEmailUID === uid)) {
          emailToUpdate = identity.email;
        }
        if (!pgPool && (!currentEmailUID || currentEmailUID === uid) && db.emailIndex[identity.email] !== uid) {
          db.emailIndex[identity.email] = uid;
        }
      } else if (!user.email && identity.email) {
        emailToUpdate = identity.email;
      }

      if (emailToUpdate) {
        if (!pgPool) user.email = emailToUpdate;
        await persistPG(async () => {
          await DB.updateUser(pgPool, uid, { email: emailToUpdate });
        });
      }

      const appleIdentity = await upsertAppleAuthIdentityAsync(uid, identity.subject, identity.email, identity.emailVerified);

      const accessToken = makeAccessToken(uid, "apple");
      const refreshToken = await issueStoredRefreshTokenAsync(uid, "apple");

      user = await getUser(uid);
      return res.status(200).json(await authSuccessPayloadAsync(
        user,
        "apple",
        user.email || appleIdentity.email || null,
        accessToken,
        refreshToken
      ));
    } catch (e) {
      const message = String(e?.message || "").toLowerCase();
      if (message.includes("token") || message.includes("jwt") || message.includes("audience") || message.includes("issuer")) {
        return res.status(401).json({ message: "invalid apple token" });
      }
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.post("/v1/auth/link-email-password", authRateLimiter, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const user = await getUser(uid);
      if (!user) return res.status(404).json({ message: "account not found" });

      const email = normalizeEmail(req.body?.email);
      const password = String(req.body?.password || "");
      if (!email || !email.includes("@")) return res.status(400).json({ message: "invalid email" });
      if (!isStrongPassword(password)) {
        return res.status(400).json({ message: "password must be at least 8 characters and include a letter, number, and special character" });
      }

      if (await userHasEmailPasswordAsync(uid)) {
        return res.status(409).json({ message: "email password already linked" });
      }

      const existingEmailIdentity = await findEmailPasswordIdentityAsync(email);
      if (existingEmailIdentity && existingEmailIdentity.userID !== uid) {
        return res.status(409).json({ message: "email already in use by another account" });
      }

      const passwordHash = await hashPassword(password);
      const now = nowUnix();
      const identityID = `aid_${randHex(12)}`;
      const identityObj = {
        id: identityID,
        userID: uid,
        provider: "email_password",
        providerSubject: email,
        email,
        emailVerified: false,
        passwordHash,
        createdAt: now,
        updatedAt: now
      };

      if (!pgPool) {
        db.authIdentities[identityID] = identityObj;
        if (!user.email) user.email = email;
        if (!db.emailIndex[email]) db.emailIndex[email] = uid;
      }

      const userEmail = user.email || email;
      await persistPG(async () => {
        await DB.insertAuthIdentity(pgPool, identityObj);
        await DB.updateUser(pgPool, uid, { email: userEmail });
      });
      if (!pgPool) await saveDB();
      const verificationToken = await issueEmailVerificationTokenAsync(uid, email);
      await deliverVerificationEmail(email, verificationToken);

      return res.status(200).json({
        ok: true,
        email,
        emailVerificationRequired: true
      });
    } catch (e) {
      if (e?.message === "missing bearer" || e?.message === "invalid token") {
        return res.status(401).json({ message: "unauthorized" });
      }
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.post("/v1/auth/email/register", authRateLimiter, async (req, res) => {
    return res.status(410).json({
      code: "legacy_auth_endpoint_disabled",
      message: "legacy endpoint disabled; use /v1/auth/register"
    });
  });

  app.post("/v1/auth/email/login", authLoginRateLimiter, (req, res) => {
    return res.status(410).json({
      code: "legacy_auth_endpoint_disabled",
      message: "legacy endpoint disabled; use /v1/auth/login"
    });
  });

  app.post("/v1/auth/oauth", authLoginRateLimiter, async (req, res) => {
    try {
      const provider = String(req.body?.provider || "").trim().toLowerCase();
      const idToken = String(req.body?.idToken || "").trim();
      if (provider !== "apple" && provider !== "google") return res.status(400).json({ message: "provider must be apple or google" });
      if (!idToken) return res.status(400).json({ message: "idToken required" });
      const identity = await verifyOAuthIdentity(provider, idToken);
      const modernKey = oauthSubjectKey(provider, identity.subject);
      const legacyKey = oauthLegacyKey(provider, idToken);
      const modernOAuthUID = await getOAuthUserAsync(modernKey);
      const legacyOAuthUID = await getOAuthUserAsync(legacyKey);
      const modernUID = await existingUserIDAsync(modernOAuthUID);
      const legacyUID = await existingUserIDAsync(legacyOAuthUID);
      const emailUser = identity.email && identity.emailVerified
        ? await getUserByEmailAsync(identity.email)
        : null;
      const emailUID = emailUser ? await existingUserIDAsync(emailUser.id) : "";

      let uid = await chooseCanonicalOAuthUserIDAsync([
        { uid: modernUID, source: "modern" },
        { uid: legacyUID, source: "legacy" },
        { uid: emailUID, source: "email" }
      ]);

      if (modernUID && modernUID !== uid) await mergeEmptyOAuthAccountIntoAsync(modernUID, uid);
      if (legacyUID && legacyUID !== uid) await mergeEmptyOAuthAccountIntoAsync(legacyUID, uid);
      if (emailUID && emailUID !== uid) await mergeEmptyOAuthAccountIntoAsync(emailUID, uid);

      if (!uid) {
        const newUser = await createDefaultUserAsync(provider);
        uid = newUser.id;
      }

      if (modernKey) {
        if (pgPool) {
          await DB.setOAuthUser(pgPool, modernKey, uid);
        } else if (db.oauthIndex[modernKey] !== uid) {
          db.oauthIndex[modernKey] = uid;
        }
      }

      let u = await getUser(uid);
      if (!u) return res.status(500).json({ message: "user not found after oauth login" });

      if (identity.email && identity.emailVerified) {
        const currentEmailUser = await getUserByEmailAsync(identity.email);
        const currentEmailUID = currentEmailUser?.id || "";
        if (!u.email && (!currentEmailUID || currentEmailUID === uid)) {
          if (pgPool) {
            await DB.updateUser(pgPool, uid, { email: identity.email });
          } else {
            u.email = identity.email;
          }
        }
        if (!pgPool && (!currentEmailUID || currentEmailUID === uid) && db.emailIndex[identity.email] !== uid) {
          db.emailIndex[identity.email] = uid;
        }
      }

      const refreshToken = await issueStoredRefreshTokenAsync(uid, u.provider);
      u = await getUser(uid);
      return res.status(200).json(await authSuccessPayloadAsync(
        u,
        u.provider,
        u.email || null,
        makeAccessToken(uid, u.provider),
        refreshToken
      ));
    } catch (e) {
      const message = String(e?.message || "").toLowerCase();
      if (message.includes("token") || message.includes("jwt") || message.includes("audience") || message.includes("issuer")) {
        return res.status(401).json({ message: "invalid oauth token" });
      }
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.get("/v1/friends", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });
      const friendIDs = await getUserFriendIDs(uid);
      const out = [];
      for (const fid of friendIDs) {
        const f = await getUser(fid);
        if (f) out.push(await friendDTOForViewerAsync(f, true));
      }
      return res.status(200).json(out);
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/friends", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const postFriendsUser = await getUser(uid);
      if (!postFriendsUser) return res.status(404).json({ message: "user not found" });
      return res.status(409).json({ message: "direct add disabled, use /v1/friends/requests" });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.get("/v1/friends/requests", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });

      let incomingRaw, outgoingRaw;
      if (pgPool) {
        incomingRaw = await DB.getFriendRequestsTo(pgPool, uid);
        outgoingRaw = await DB.getFriendRequestsFrom(pgPool, uid);
      } else {
        incomingRaw = allFriendRequests().filter((item) => item.toUserID === uid);
        outgoingRaw = allFriendRequests().filter((item) => item.fromUserID === uid);
      }
      const incoming = (await Promise.all(incomingRaw.map(friendRequestDTOAsync))).filter(Boolean);
      const outgoing = (await Promise.all(outgoingRaw.map(friendRequestDTOAsync))).filter(Boolean);
      return res.status(200).json({ incoming, outgoing });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/friends/requests", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
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
        target = await resolveUserByInviteCodeAsync(inviteCodeRaw);
      }
      const requestedHandle = normalizeHandle(handleRaw || displayName);
      if (!target && requestedHandle) {
        target = await getUserByHandleAsync(requestedHandle);
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

      // Block check — silently reject as "not found" so blockers stay invisible
      if (await isBlockedEitherDirectionSafe(uid, target.id)) {
        return res.status(404).json({ message: "user not found" });
      }

      const areFriends = await checkAreFriends(uid, target.id);
      if (areFriends) {
        return res.status(409).json({ message: "already friends" });
      }

      let existing;
      if (pgPool) {
        existing = await DB.findPendingFriendRequest(pgPool, uid, target.id);
      } else {
        existing = findPendingFriendRequest(uid, target.id);
      }
      if (existing) {
        const dto = await friendRequestDTOAsync(existing);
        return res.status(200).json({ ok: true, request: dto, message: "好友申请已发送，等待对方通过" });
      }

      let reverse;
      if (pgPool) {
        reverse = await DB.findPendingFriendRequest(pgPool, target.id, uid);
      } else {
        reverse = findPendingFriendRequest(target.id, uid);
      }
      if (reverse) {
        return res.status(409).json({ message: "对方已向你发送申请，请在申请列表中通过" });
      }

      const reqID = `fr_${randHex(10)}`;
      const createdAt = new Date().toISOString();
      const frObj = {
        id: reqID,
        fromUserID: uid,
        toUserID: target.id,
        note,
        createdAt,
        updatedAt: createdAt
      };
      if (!pgPool) db.friendRequestsIndex[reqID] = frObj;
      await persistPG(async () => {
        await DB.insertFriendRequest(pgPool, frObj);
      });

      const notif = {
        id: `n_${randHex(10)}`,
        type: "friend_request",
        fromUserID: me.id,
        fromDisplayName: me.displayName,
        journeyID: null,
        journeyTitle: null,
        message: `${me.displayName} 向你发送了好友申请`,
        createdAt: new Date().toISOString(),
        read: false
      };
      await pushNotificationAndPersist(target.id, notif, {
        title: "StreetStamps",
        body: `${me.displayName} 向你发送了好友申请`
      });

      return res.status(200).json({
        ok: true,
        request: await friendRequestDTOAsync(frObj),
        message: "好友申请已发送，等待对方通过"
      });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/friends/requests/:requestID/accept", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });
      const requestID = String(req.params.requestID || "").trim();
      if (!requestID) return res.status(400).json({ message: "request id required" });

      const pending = pgPool
        ? await DB.getFriendRequest(pgPool, requestID)
        : db.friendRequestsIndex[requestID];
      if (!pending) return res.status(404).json({ message: "request not found" });
      if (pending.toUserID !== uid) return res.status(403).json({ message: "forbidden" });

      const fromUser = await getUser(pending.fromUserID);
      if (!fromUser) {
        if (!pgPool) removeFriendRequestByID(requestID);
        await persistPG(async () => {
          await DB.deleteFriendRequest(pgPool, requestID);
        });
        return res.status(404).json({ message: "request sender not found" });
      }

      if (await isBlockedEitherDirectionSafe(uid, fromUser.id)) {
        if (!pgPool) removeFriendRequestsBetween(me.id, fromUser.id);
        await persistPG(async () => {
          await DB.deleteFriendRequestsBetween(pgPool, me.id, fromUser.id);
        });
        return res.status(404).json({ message: "request not found" });
      }

      const deletedRequestIDs = pgPool
        ? await DB.collectFriendRequestIDsBetween(pgPool, me.id, fromUser.id)
        : collectFriendRequestIDsBetween(me.id, fromUser.id);
      if (!pgPool) {
        appendUnique(me.friendIDs, fromUser.id);
        appendUnique(fromUser.friendIDs, me.id);
        removeFriendRequestsBetween(me.id, fromUser.id);
      }

      const notif = {
        id: `n_${randHex(10)}`,
        type: "friend_request_accepted",
        fromUserID: me.id,
        fromDisplayName: me.displayName,
        journeyID: null,
        journeyTitle: null,
        message: `${me.displayName} 通过了你的好友申请`,
        createdAt: new Date().toISOString(),
        read: false
      };

      await persistPGTx(async (client) => {
        await DB.addFriendship(client, me.id, fromUser.id);
        for (const rid of deletedRequestIDs) await DB.deleteFriendRequest(client, rid);
        await DB.insertNotification(client, {
          id: notif.id, userID: fromUser.id, type: notif.type,
          fromUserID: notif.fromUserID, fromDisplayName: notif.fromDisplayName,
          journeyID: null, journeyTitle: null,
          message: notif.message, read: false,
          createdAt: notif.createdAt,
        });
      });
      if (!pgPool) {
        ensureUserNotifications(fromUser);
        fromUser.notifications.unshift(notif);
      }
      fireRemotePush(fromUser.id, {
        title: "StreetStamps",
        body: `${me.displayName} 通过了你的好友申请`
      });

      return res.status(200).json({
        ok: true,
        friend: await friendDTOForViewerAsync(fromUser, true),
        message: "已通过好友申请"
      });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/friends/requests/:requestID/reject", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });
      const requestID = String(req.params.requestID || "").trim();
      if (!requestID) return res.status(400).json({ message: "request id required" });

      const pending = pgPool
        ? await DB.getFriendRequest(pgPool, requestID)
        : db.friendRequestsIndex[requestID];
      if (!pending) return res.status(404).json({ message: "request not found" });
      if (pending.toUserID !== uid) return res.status(403).json({ message: "forbidden" });

      if (!pgPool) removeFriendRequestByID(requestID);
      await persistPG(async () => {
        await DB.deleteFriendRequest(pgPool, requestID);
      });
      return res.status(200).json({ ok: true, message: "已拒绝好友申请" });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.delete("/v1/friends/:friendID", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });
      const fid = String(req.params.friendID || "").trim();
      if (!fid) return res.status(400).json({ message: "friend id required" });

      const deletedRequestIDs = pgPool
        ? await DB.collectFriendRequestIDsBetween(pgPool, uid, fid)
        : collectFriendRequestIDsBetween(uid, fid);
      if (!pgPool) {
        me.friendIDs = removeID(me.friendIDs || [], fid);
        const f = db.users[fid];
        if (f) f.friendIDs = removeID(f.friendIDs || [], uid);
        removeFriendRequestsBetween(uid, fid);
      }
      await persistPGTx(async (client) => {
        await DB.removeFriendship(client, uid, fid);
        for (const rid of deletedRequestIDs) await DB.deleteFriendRequest(client, rid);
      });
      return res.status(200).json({});
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  // ── Block / Unblock ─────────────────────────────────────────
  app.post("/v1/users/:userID/block", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const targetID = String(req.params.userID || "").trim();
      if (!targetID || targetID === uid) return res.status(400).json({ message: "invalid target" });
      if (!pgPool) return res.status(501).json({ message: "blocking requires PG" });
      await DB.blockUser(pgPool, uid, targetID);
      await persistPGTx(async (client) => {
        await DB.removeFriendship(client, uid, targetID);
        await DB.deleteFriendRequestsBetween(client, uid, targetID);
      });
      return res.status(200).json({});
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.delete("/v1/users/:userID/block", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const targetID = String(req.params.userID || "").trim();
      if (!targetID) return res.status(400).json({ message: "invalid target" });
      if (!pgPool) return res.status(501).json({ message: "blocking requires PG" });
      await DB.unblockUser(pgPool, uid, targetID);
      return res.status(200).json({});
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.get("/v1/blocks", async (req, res) => {
    try {
      const uid = parseBearer(req);
      if (!pgPool) return res.status(200).json({ blocks: [] });
      const blockedIDs = await DB.getBlockedUserIDs(pgPool, uid);
      const blockedUsers = blockedIDs.length ? await DB.getUsersByIDs(pgPool, blockedIDs) : {};
      const list = blockedIDs.map((id) => {
        const u = blockedUsers[id];
        return { id, displayName: u?.displayName || "Unknown", handle: u?.handle || null };
      });
      return res.status(200).json({ blocks: list });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  // ── Reports ────────────────────────────────────────────────
  app.post("/v1/reports", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const reportedUserID = String(req.body?.reportedUserID || "").trim();
      const contentType = String(req.body?.contentType || "user").trim();
      const contentID = String(req.body?.contentID || "").trim() || null;
      const reason = String(req.body?.reason || "").trim();
      const detail = String(req.body?.detail || "").trim();

      if (!reportedUserID) return res.status(400).json({ message: "reportedUserID required" });
      const allowedTypes = ["user", "journey", "postcard"];
      if (!allowedTypes.includes(contentType)) return res.status(400).json({ message: "invalid contentType" });
      const allowedReasons = ["spam", "harassment", "inappropriate", "other"];
      if (!allowedReasons.includes(reason)) return res.status(400).json({ message: "invalid reason" });
      if (!pgPool) return res.status(501).json({ message: "reports require PG" });

      const reportID = `rpt_${crypto.randomUUID().replace(/-/g, "").slice(0, 20)}`;
      await DB.insertReport(pgPool, {
        id: reportID,
        reporterUserID: uid,
        reportedUserID,
        contentType,
        contentID,
        reason,
        detail,
      });
      return res.status(200).json({ reportID });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/journeys/migrate", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });
      const journeys = Array.isArray(req.body?.journeys) ? req.body.journeys : [];
      const unlockedCityCards = Array.isArray(req.body?.unlockedCityCards) ? req.body.unlockedCityCards : [];
      const removedJourneyIDs = Array.isArray(req.body?.removedJourneyIDs) ? req.body.removedJourneyIDs : [];
      const snapshotComplete = parseTruthy(req.body?.snapshotComplete);

      if (!pgPool) {
        me.journeys = mergeJourneyPayloads(me.journeys || [], journeys, removedJourneyIDs, snapshotComplete, uid);
        me.cityCards = mergeCityCardPayloads(me.cityCards || [], unlockedCityCards, snapshotComplete);
      }

      let finalJourneyCount, finalCityCardCount;
      if (pgPool) {
        for (const j of journeys) await DB.upsertJourney(pgPool, uid, j);
        if (removedJourneyIDs.length) await DB.deleteJourneys(pgPool, uid, removedJourneyIDs);
        // For city cards, merge with existing then replace
        const existingCards = await DB.getCityCardsByUser(pgPool, uid);
        const mergedCards = mergeCityCardPayloads(existingCards, unlockedCityCards, snapshotComplete);
        await DB.replaceCityCards(pgPool, uid, mergedCards);
        finalJourneyCount = (await DB.getJourneysByUser(pgPool, uid)).length;
        finalCityCardCount = mergedCards.length;
      } else {
        await persistPG(async () => {
          for (const j of journeys) await DB.upsertJourney(pgPool, uid, j);
          if (removedJourneyIDs.length) await DB.deleteJourneys(pgPool, uid, removedJourneyIDs);
          await DB.replaceCityCards(pgPool, uid, me.cityCards);
        });
        finalJourneyCount = me.journeys.length;
        finalCityCardCount = me.cityCards.length;
      }
      return res.status(200).json({ journeys: finalJourneyCount, cityCards: finalCityCardCount });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/journeys/likes/batch", readRateLimiter, async (req, res) => {
    try {
      const viewerID = parseBearer(req);
      const viewer = await getUser(viewerID);
      if (!viewer) return res.status(404).json({ message: "user not found" });

      const ownerUserIDRaw = String(req.body?.ownerUserID || "").trim();
      const ownerUserID = ownerUserIDRaw || viewerID;
      const owner = await getUser(ownerUserID);
      if (!owner) return res.status(404).json({ message: "user not found" });

      const ids = Array.isArray(req.body?.journeyIDs)
        ? req.body.journeyIDs.map((x) => String(x || "").trim()).filter(Boolean)
        : [];
      const uniqIDs = [...new Set(ids)];

      const ownerJourneys = await getUserJourneys(ownerUserID);
      const ownerJourneyByID = new Map(ownerJourneys.map((j) => [String(j.id), j]));

      if (pgPool) {
        // Batch fetch likes from PG
        const viewableJIDs = [];
        for (const jid of uniqIDs) {
          const journey = ownerJourneyByID.get(jid);
          if (journey && await canViewJourneyAsync(viewerID, ownerUserID, journey)) viewableJIDs.push(jid);
        }
        const keys = viewableJIDs.map((jid) => ({ ownerUserID, journeyID: jid }));
        const likesBatch = await DB.batchGetJourneyLikes(pgPool, keys);
        const viewableSet = new Set(viewableJIDs);

        const items = [];
        for (const journeyID of uniqIDs) {
          const journey = ownerJourneyByID.get(journeyID);
          if (!journey || !viewableSet.has(journeyID)) {
            items.push({ journeyID, likes: 0, likedByMe: false });
            continue;
          }
          const record = likesBatch[`${ownerUserID}:${journeyID}`];
          const likerIDs = record ? record.likerIDs : [];
          items.push({
            journeyID,
            likes: likerIDs.length,
            likedByMe: likerIDs.includes(viewerID)
          });
        }
        return res.status(200).json({ items });
      }

      // Fallback: in-memory
      const items = [];
      for (const journeyID of uniqIDs) {
        const journey = ownerJourneyByID.get(journeyID);
        if (!journey || !canViewJourney(viewer, owner, journey)) {
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
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.get("/v1/journeys/:ownerUserID/:journeyID/likes", readRateLimiter, async (req, res) => {
    try {
      const viewerID = parseBearer(req);
      const ownerUserID = String(req.params.ownerUserID || "").trim();
      const journeyID = String(req.params.journeyID || "").trim();
      if (!ownerUserID || !journeyID) return res.status(400).json({ message: "ownerUserID and journeyID required" });

      const viewer = await getUser(viewerID);
      const owner = await getUser(ownerUserID);
      if (!viewer || !owner) return res.status(404).json({ message: "user not found" });
      if (viewerID !== ownerUserID && await isBlockedEitherDirectionSafe(viewerID, ownerUserID)) {
        return res.status(404).json({ message: "user not found" });
      }

      const ownerJourneys = await getUserJourneys(ownerUserID);
      const journey = ownerJourneys.find((x) => String(x.id) === journeyID);
      if (!journey) return res.status(404).json({ message: "journey not found" });
      if (pgPool) {
        if (!(await canViewJourneyAsync(viewerID, ownerUserID, journey))) return res.status(403).json({ message: "forbidden" });
        const likers = await DB.getJourneyLikers(pgPool, ownerUserID, journeyID);
        const likerIDs = likers.map((l) => l.likerUserID);
        const likerUsers = likerIDs.length ? await DB.getUsersByIDs(pgPool, likerIDs) : {};
        const items = likers
          .map((l) => {
            const liker = likerUsers[l.likerUserID];
            if (!liker) return null;
            return {
              userID: l.likerUserID,
              displayName: String(liker.displayName || l.likerUserID),
              likedAt: l.createdAt
            };
          })
          .filter(Boolean)
          .sort((a, b) => Date.parse(b.likedAt || "") - Date.parse(a.likedAt || ""));
        return res.status(200).json({ items });
      }

      // Fallback: in-memory
      if (!canViewJourney(viewer, owner, journey)) return res.status(403).json({ message: "forbidden" });
      const record = ensureLikeRecord(ownerUserID, journeyID);
      const likedAtByUserID = record.likedAtByUserID || {};
      const items = (record.likerIDs || [])
        .map((userID) => {
          const liker = db.users[userID];
          if (!liker) return null;
          return {
            userID,
            displayName: String(liker.displayName || userID),
            likedAt: likedAtByUserID[userID] || record.updatedAt || new Date().toISOString()
          };
        })
        .filter(Boolean)
        .sort((a, b) => Date.parse(b.likedAt || "") - Date.parse(a.likedAt || ""));

      return res.status(200).json({ items });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/journeys/:ownerUserID/:journeyID/like", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const viewerID = parseBearer(req);
      const ownerUserID = String(req.params.ownerUserID || "").trim();
      const journeyID = String(req.params.journeyID || "").trim();
      if (!ownerUserID || !journeyID) return res.status(400).json({ message: "ownerUserID and journeyID required" });

      const viewer = await getUser(viewerID);
      const owner = await getUser(ownerUserID);
      if (!viewer || !owner) return res.status(404).json({ message: "user not found" });
      if (viewerID !== ownerUserID && await isBlockedEitherDirectionSafe(viewerID, ownerUserID)) {
        return res.status(404).json({ message: "user not found" });
      }
      const ownerJourneys = await getUserJourneys(ownerUserID);
      const journey = ownerJourneys.find((x) => String(x.id) === journeyID);
      if (!journey) return res.status(404).json({ message: "journey not found" });
      if (pgPool) {
        if (!(await canViewJourneyAsync(viewerID, ownerUserID, journey))) return res.status(403).json({ message: "forbidden" });
      } else {
        if (!canViewJourney(viewer, owner, journey)) return res.status(403).json({ message: "forbidden" });
      }

      if (pgPool) {
        await DB.addJourneyLike(pgPool, ownerUserID, journeyID, viewerID);
      } else {
        const record = ensureLikeRecord(ownerUserID, journeyID);
        if (!record.likerIDs.includes(viewerID)) {
          record.likerIDs.push(viewerID);
          const now = new Date().toISOString();
          record.likedAtByUserID[viewerID] = now;
          record.updatedAt = now;
        }
      }

      if (viewerID !== ownerUserID) {
        const notif = {
          id: `n_${randHex(10)}`,
          type: "journey_like",
          fromUserID: viewerID,
          fromDisplayName: viewer.displayName,
          journeyID,
          journeyTitle: journey.title || journey.name || null,
          message: `${viewer.displayName} 赞了你的旅程`,
          createdAt: new Date().toISOString(),
          read: false
        };
        await pushNotificationAndPersist(ownerUserID, notif, {
          title: "StreetStamps",
          body: `${viewer.displayName} 赞了你的旅程`
        });
      }

      const likeCount = pgPool
        ? await DB.getJourneyLikeCount(pgPool, ownerUserID, journeyID)
        : ensureLikeRecord(ownerUserID, journeyID).likerIDs.length;

      return res.status(200).json({
        ownerUserID,
        journeyID,
        likes: likeCount,
        likedByMe: true
      });
    } catch (err) {
      const isAuth = err && (err.name === "JsonWebTokenError" || err.name === "TokenExpiredError" || err.message === "missing bearer token");
      if (isAuth) return res.status(401).json({ message: "unauthorized" });
      console.error("[like] unexpected error:", err);
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.delete("/v1/journeys/:ownerUserID/:journeyID/like", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const viewerID = parseBearer(req);
      const ownerUserID = String(req.params.ownerUserID || "").trim();
      const journeyID = String(req.params.journeyID || "").trim();
      if (!ownerUserID || !journeyID) return res.status(400).json({ message: "ownerUserID and journeyID required" });

      const owner = await getUser(ownerUserID);
      if (!owner) return res.status(404).json({ message: "user not found" });
      if (viewerID !== ownerUserID && await isBlockedEitherDirectionSafe(viewerID, ownerUserID)) {
        return res.status(404).json({ message: "user not found" });
      }

      if (pgPool) {
        await DB.removeJourneyLike(pgPool, ownerUserID, journeyID, viewerID);
      } else {
        const record = ensureLikeRecord(ownerUserID, journeyID);
        record.likerIDs = (record.likerIDs || []).filter((x) => x !== viewerID);
        delete record.likedAtByUserID[viewerID];
        record.updatedAt = new Date().toISOString();
      }

      const likeCount = pgPool
        ? await DB.getJourneyLikeCount(pgPool, ownerUserID, journeyID)
        : ensureLikeRecord(ownerUserID, journeyID).likerIDs.length;

      return res.status(200).json({
        ownerUserID,
        journeyID,
        likes: likeCount,
        likedByMe: false
      });
    } catch (err) {
      const isAuth = err && (err.name === "JsonWebTokenError" || err.name === "TokenExpiredError" || err.message === "missing bearer token");
      if (isAuth) return res.status(401).json({ message: "unauthorized" });
      console.error("[unlike] unexpected error:", err);
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.post("/v1/postcards/send", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    const requestStartedAt = timingNowNs();
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });

      const toUserID = String(req.body?.toUserID || "").trim();
      const cityID = String(req.body?.cityID || "").trim();
      const cityJourneyCount = Math.max(1, Number.parseInt(String(req.body?.cityJourneyCount ?? ""), 10) || 1);
      const cityNameRaw = String(req.body?.cityName || "").trim();
      const cityName = cityNameRaw || cityID;
      const messageText = String(req.body?.messageText || "").trim();
      const photoURL = absolutizePostcardPhotoURL(req.body?.photoURL, req);
      const clientDraftID = String(req.body?.clientDraftID || "").trim();
      const allowedCityIDs = Array.isArray(req.body?.allowedCityIDs)
        ? req.body.allowedCityIDs.map((x) => String(x || "").trim()).filter(Boolean)
        : [];

      if (!toUserID || !cityID || !clientDraftID) {
        return res.status(400).json({ message: "toUserID, cityID and clientDraftID are required" });
      }
      if (!photoURL) {
        return res.status(400).json({ message: "photoURL required" });
      }
      if (!/^https?:\/\//i.test(photoURL)) {
        return res.status(400).json({ message: "photoURL must be an HTTP(S) URL" });
      }
      if (messageText.length > 80) {
        return res.status(400).json({ code: "message_too_long", message: "messageText must be <= 80 chars" });
      }

      const target = await resolveUserByAnyIDAsync(toUserID);
      if (!target) return res.status(404).json({ message: "target user not found" });
      if (uid === target.id) return res.status(400).json({ message: "cannot send postcard to yourself" });
      if (await isBlockedEitherDirectionSafe(uid, target.id)) return res.status(403).json({ message: "blocked" });
      if (!(await checkAreFriends(uid, target.id))) return res.status(403).json({ message: "friends only" });

      // Get sent postcards for quota check
      const sentPostcards = pgPool
        ? await DB.getPostcardsForUser(pgPool, uid, "sent")
        : (ensurePostcardCollections(me), me.sentPostcards);

      const membershipTier = String(req.body?.membershipTier || "free").trim();
      const rule = canSendPostcard({
        sentPostcards,
        toUserID,
        cityID,
        cityJourneyCount,
        clientDraftID,
        allowedCityIDs,
        membershipTier
      });

      if (rule.idempotentHit) {
        const hit = rule.idempotentHit;
        return res.status(200).json({
          messageID: hit.messageID,
          sentAt: hit.sentAt,
          idempotent: true
        });
      }

      if (!rule.ok) {
        if (rule.reason === "city_not_allowed") {
          return res.status(400).json({ code: rule.reason, message: "city not allowed" });
        }
        if (rule.reason === "city_friend_quota_exceeded") {
          return res.status(409).json({
            code: rule.reason,
            message: "friend city postcard limit reached"
          });
        }
        if (rule.reason === "city_total_quota_exceeded") {
          return res.status(409).json({
            code: rule.reason,
            message: "city postcard limit reached"
          });
        }
        return res.status(409).json({ code: rule.reason, message: "postcard quota exceeded" });
      }

      const nowISO = new Date().toISOString();
      const canonicalMessage = {
        messageID: `pm_${randHex(12)}`,
        type: "postcard",
        fromUserID: me.id,
        fromDisplayName: me.displayName,
        toUserID: target.id,
        toDisplayName: target.displayName,
        cityID,
        cityName,
        photoURL,
        messageText,
        sentAt: nowISO,
        clientDraftID,
        status: "sent"
      };

      if (!pgPool) {
        upsertPostcard(canonicalMessage);
        ensurePostcardCollections(me);
        ensurePostcardCollections(target);
        me.sentPostcards.unshift(canonicalMessage);
        target.receivedPostcards.unshift(canonicalMessage);
        if (me.sentPostcards.length > 1000) me.sentPostcards = me.sentPostcards.slice(0, 1000);
        if (target.receivedPostcards.length > 1000) target.receivedPostcards = target.receivedPostcards.slice(0, 1000);
      }

      const notif = {
        id: `n_${randHex(10)}`,
        type: "postcard_received",
        fromUserID: me.id,
        fromDisplayName: me.displayName,
        journeyID: null,
        journeyTitle: null,
        message: `${me.displayName} 给你寄了一张明信片`,
        createdAt: nowISO,
        read: false
      };

      const saveStartedAt = timingNowNs();
      await persistPGTx(async (client) => {
        await DB.insertPostcard(client, canonicalMessage);
        await DB.insertNotification(client, {
          id: notif.id, userID: target.id, type: notif.type,
          fromUserID: notif.fromUserID, fromDisplayName: notif.fromDisplayName,
          journeyID: null, journeyTitle: null,
          message: notif.message, read: false,
          createdAt: notif.createdAt,
        });
      });
      if (!pgPool) {
        ensureUserNotifications(target);
        target.notifications.unshift(notif);
      }
      fireRemotePush(target.id, {
        title: "StreetStamps",
        body: `${me.displayName} 给你寄了一张明信片`
      });
      const saveDurationMs = elapsedMs(saveStartedAt);

      logTiming("postcard_send", {
        userID: uid,
        toUserID: target.id,
        cityID,
        saveDurationMs,
        totalDurationMs: elapsedMs(requestStartedAt)
      });

      return res.status(200).json({
        messageID: canonicalMessage.messageID,
        sentAt: canonicalMessage.sentAt
      });
    } catch (error) {
      logTiming("postcard_send_error", {
        totalDurationMs: elapsedMs(requestStartedAt),
        message: error && error.message ? error.message : "unauthorized"
      });
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.get("/v1/postcards", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });

      const boxRaw = String(req.query?.box || "sent").trim().toLowerCase();
      const box = boxRaw === "received" ? "received" : "sent";

      let source;
      if (pgPool) {
        source = await DB.getPostcardsForUser(pgPool, uid, box);
      } else {
        ensurePostcardCollections(me);
        source = box === "received" ? (me.receivedPostcards || []) : (me.sentPostcards || []);
      }

      const items = await Promise.all(
        source
          .map((item) => normalizePostcardMessage(item))
          .filter(Boolean)
          .filter((item) => String(item.photoURL || "").trim().length > 0)
          .map(async (item) => {
            const reactionPayload = await postcardReactionPayloadForViewerAsync(uid, item, box);
            return {
              ...item,
              photoURL: absolutizePostcardPhotoURL(item.photoURL, req),
              reaction: reactionPayload.reaction,
              myReaction: reactionPayload.myReaction,
              peerReaction: reactionPayload.peerReaction
            };
          })
      );
      items.sort((a, b) => Date.parse(b.sentAt || "") - Date.parse(a.sentAt || ""));
      return res.status(200).json({ items, cursor: null });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/postcards/:messageID/view", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });

      const messageID = String(req.params.messageID || "").trim();
      if (!messageID) return res.status(400).json({ message: "messageID required" });

      // Find the postcard
      let postcard;
      if (pgPool) {
        postcard = await DB.getPostcardByID(pgPool, messageID);
        if (!postcard || postcard.toUserID !== uid) postcard = null;
      } else {
        ensurePostcardCollections(me);
        postcard = (me.receivedPostcards || []).find((p) => p.messageID === messageID);
      }
      if (!postcard) return res.status(404).json({ message: "postcard not found" });

      const sender = await getUser(postcard.fromUserID);
      if (!sender) return res.status(404).json({ message: "sender not found" });

      if (await isBlockedEitherDirectionSafe(uid, postcard.fromUserID)) {
        return res.status(404).json({ message: "postcard not found" });
      }

      // Check if reaction already exists
      let existingReaction;
      if (pgPool) {
        existingReaction = await DB.getPostcardReaction(pgPool, messageID, me.id);
      } else {
        existingReaction = sender.postcardReactions?.[messageID];
      }

      if (!existingReaction) {
        const reactionObj = {
          id: `pr_${randHex(12)}`,
          postcardMessageID: messageID,
          fromUserID: me.id,
          viewedAt: new Date().toISOString(),
          reactionEmoji: null,
          comment: null,
          reactedAt: null
        };
        if (!pgPool) {
          if (!sender.postcardReactions) sender.postcardReactions = {};
          sender.postcardReactions[messageID] = reactionObj;
        }
        await persistPG(async () => {
          await DB.upsertPostcardReaction(pgPool, reactionObj);
        });
      }

      return res.status(200).json({ success: true });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/postcards/:messageID/react", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });

      const messageID = String(req.params.messageID || "").trim();
      const reactionEmoji = String(req.body?.reactionEmoji || "").trim();
      const comment = String(req.body?.comment || "").trim();

      if (!messageID) return res.status(400).json({ message: "messageID required" });
      if (comment.length > 50) return res.status(400).json({ message: "comment too long (max 50 chars)" });

      // Find the postcard
      let postcard;
      if (pgPool) {
        postcard = await DB.getPostcardByID(pgPool, messageID);
        if (!postcard || postcard.toUserID !== uid) postcard = null;
      } else {
        ensurePostcardCollections(me);
        postcard = (me.receivedPostcards || []).find((p) => p.messageID === messageID);
      }
      if (!postcard) return res.status(404).json({ message: "postcard not found" });

      const sender = await getUser(postcard.fromUserID);
      if (!sender) return res.status(404).json({ message: "sender not found" });

      if (await isBlockedEitherDirectionSafe(uid, postcard.fromUserID)) {
        return res.status(404).json({ message: "postcard not found" });
      }

      // Get existing reaction
      let existing;
      if (pgPool) {
        existing = await DB.getPostcardReaction(pgPool, messageID, me.id);
      } else {
        if (!sender.postcardReactions) sender.postcardReactions = {};
        existing = sender.postcardReactions[messageID];
      }
      const nowISO = new Date().toISOString();

      const reactionObj = {
        id: existing?.id || `pr_${randHex(12)}`,
        postcardMessageID: messageID,
        fromUserID: me.id,
        viewedAt: existing?.viewedAt || nowISO,
        reactionEmoji: reactionEmoji || null,
        comment: comment || null,
        reactedAt: nowISO
      };

      if (!pgPool) {
        sender.postcardReactions[messageID] = reactionObj;
      }

      // Build and persist notification
      const notifBody = reactionEmoji
        ? `${me.displayName} 回应了你的明信片 ${reactionEmoji}`
        : `${me.displayName} 回复了你的明信片`;
      const notif = {
        id: `n_${randHex(10)}`,
        type: "postcard_reaction",
        fromUserID: me.id,
        fromDisplayName: me.displayName,
        journeyID: null,
        journeyTitle: null,
        message: notifBody,
        createdAt: nowISO,
        read: false
      };

      await persistPG(async () => {
        await DB.upsertPostcardReaction(pgPool, reactionObj);
      });
      await pushNotificationAndPersist(sender.id, notif, {
        title: "StreetStamps",
        body: notifBody
      });

      return res.status(200).json({
        reaction: reactionObj
      });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.get("/v1/notifications", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });
      const source = await getUserNotifications(uid);
      const unreadOnlyRaw = String(req.query.unreadOnly || "1").trim().toLowerCase();
      const unreadOnly = !(unreadOnlyRaw === "0" || unreadOnlyRaw === "false" || unreadOnlyRaw === "no");
      const filtered = unreadOnly ? source.filter((x) => !x.read) : source;
      const items = filtered.map((item) => {
        if (!item || item.type !== "postcard_received") return item;
        return {
          ...item,
          photoURL: absolutizePostcardPhotoURL(item.photoURL, req)
        };
      });
      return res.status(200).json({ items });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/notifications/read", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });

      const markAll = Boolean(req.body?.all);
      const ids = Array.isArray(req.body?.ids)
        ? req.body.ids.map((x) => String(x || "").trim()).filter(Boolean)
        : [];

      if (pgPool) {
        if (markAll) {
          await DB.markAllNotificationsRead(pgPool, uid);
        } else if (ids.length) {
          await DB.markNotificationsRead(pgPool, uid, ids);
        }
      } else {
        ensureUserNotifications(me);
        const idSet = new Set(ids);
        me.notifications = (me.notifications || []).map((item) => {
          const shouldRead = markAll || idSet.has(String(item.id));
          if (shouldRead && !item.read) return { ...item, read: true };
          return item;
        });
        await saveDB();
      }
      return res.status(200).json({ ok: true });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  // ---- Push Token Registration ----
  app.put("/v1/push-token", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });
      const token = String(req.body?.token || "").trim();
      const platform = String(req.body?.platform || "ios").trim();
      if (!token) return res.status(400).json({ message: "token required" });
      await DB.upsertPushToken(pgPool, uid, token, platform);
      return res.status(200).json({ ok: true });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.delete("/v1/push-token", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const token = String(req.body?.token || "").trim();
      if (!token) return res.status(400).json({ message: "token required" });
      await DB.deletePushToken(pgPool, uid, token);
      return res.status(200).json({ ok: true });
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.get("/v1/profile/me", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });
      return res.status(200).json(await profileDTOForViewerAsync(me, true, true));
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/profile/:userID/stomp", writeRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const viewerID = parseBearer(req);
      const targetID = String(req.params.userID || "").trim();
      if (!targetID) return res.status(400).json({ message: "target user id required" });

      const viewer = await getUser(viewerID);
      const target = await getUser(targetID);
      if (!viewer || !target) return res.status(404).json({ message: "user not found" });
      if (viewerID === targetID) return res.status(400).json({ message: "cannot stomp yourself" });
      if (!(await checkAreFriends(viewerID, targetID))) return res.status(403).json({ message: "friends only" });

      const notification = {
        id: `n_${randHex(10)}`,
        type: "profile_stomp",
        fromUserID: viewer.id,
        fromDisplayName: viewer.displayName,
        journeyID: null,
        journeyTitle: null,
        message: `${viewer.displayName}在你的沙发上坐了一坐`,
        createdAt: new Date().toISOString(),
        read: false
      };
      await pushNotificationAndPersist(targetID, notification, {
        title: "StreetStamps",
        body: `${viewer.displayName}在你的沙发上坐了一坐`
      });
      return res.status(200).json({ ok: true, message: `已踩一踩 ${target.displayName} 的主页` });
    } catch (err) {
      const isAuth = err && (err.name === "JsonWebTokenError" || err.name === "TokenExpiredError" || err.message === "missing bearer" || err.message === "invalid token");
      if (isAuth) return res.status(401).json({ message: "unauthorized" });
      console.error("[stomp] unexpected error:", err);
      return res.status(500).json({ message: "internal error" });
    }
  });

  const updateExclusiveID = async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });

      const incoming = String(req.body?.exclusiveID || req.body?.handle || "").trim();
      const current = normalizeHandle(me.handle);
      const next = normalizeHandle(incoming);
      if (!next) {
        return res.status(400).json({ message: "invalid exclusive id" });
      }
      if (next === current) {
        return res.status(200).json(await profileDTOForViewerAsync(me, true, true));
      }
      if (me.handleChangeUsed) {
        return res.status(403).json({ message: "exclusive id can only be changed once" });
      }

      const result = await setUserHandleAsync(uid, incoming, { strict: true });
      if (!result.ok) {
        if (result.code === "invalid_handle") {
          return res.status(400).json({ message: "invalid exclusive id" });
        }
        if (result.code === "handle_taken") {
          return res.status(409).json({ message: "exclusive id already taken" });
        }
        return res.status(400).json({ message: "exclusive id update failed" });
      }

      if (!pgPool) me.handleChangeUsed = true;
      await persistPG(async () => {
        await DB.updateUser(pgPool, uid, { handleChangeUsed: true });
      });
      const updated = await getUser(uid);
      return res.status(200).json(await profileDTOForViewerAsync(updated, true, true));
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  };

  app.patch("/v1/profile/exclusive-id", profileWriteRateLimiter, rejectWhenWriteFrozen, updateExclusiveID);
  app.patch("/v1/profile/handle", profileWriteRateLimiter, rejectWhenWriteFrozen, updateExclusiveID);

  app.patch("/v1/profile/display-name", profileWriteRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });

      const nextName = normalizeDisplayName(req.body?.displayName);
      if (!nextName) return res.status(400).json({ message: "invalid display name" });
      if (!(await canUseDisplayNameAsync(nextName, uid))) {
        return res.status(409).json({ message: "display name already taken" });
      }

      if (!pgPool) me.displayName = nextName;
      await persistPG(async () => {
        await DB.updateUser(pgPool, uid, { displayName: nextName });
      });
      const updated = await getUser(uid);
      return res.status(200).json(await profileDTOForViewerAsync(updated, true, true));
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.patch("/v1/profile/visibility", profileWriteRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });

      const next = normalizeVisibility(req.body?.profileVisibility);
      if (!pgPool) me.profileVisibility = next;
      await persistPG(async () => {
        await DB.updateUser(pgPool, uid, { profileVisibility: next });
      });
      const updated = await getUser(uid);
      return res.status(200).json(await profileDTOForViewerAsync(updated, true, true));
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.patch("/v1/profile/bio", profileWriteRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });

      const bio = String(req.body?.bio || "").slice(0, 200);
      if (!pgPool) me.bio = bio;
      await persistPG(async () => {
        await DB.updateUser(pgPool, uid, { bio });
      });
      const updated = await getUser(uid);
      return res.status(200).json(await profileDTOForViewerAsync(updated, true, true));
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.patch("/v1/profile/loadout", profileWriteRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });

      const incoming = req.body?.loadout;
      if (!incoming || typeof incoming !== "object" || Array.isArray(incoming)) {
        return res.status(400).json({ message: "invalid loadout" });
      }

      const newLoadout = normalizeLoadout(incoming, me.loadout);
      if (!pgPool) me.loadout = newLoadout;
      await persistPG(async () => {
        await DB.updateUser(pgPool, uid, { loadout: newLoadout });
      });
      const updated = await getUser(uid);
      return res.status(200).json(await profileDTOForViewerAsync(updated, true, true));
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/profile/setup", profileWriteRateLimiter, rejectWhenWriteFrozen, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = await getUser(uid);
      if (!me) return res.status(404).json({ message: "user not found" });

      const nextName = normalizeDisplayName(req.body?.displayName);
      if (!nextName) return res.status(400).json({ message: "invalid display name" });
      if (!(await canUseDisplayNameAsync(nextName, uid))) {
        return res.status(409).json({ message: "display name already taken" });
      }

      const incoming = req.body?.loadout;
      if (!incoming || typeof incoming !== "object" || Array.isArray(incoming)) {
        return res.status(400).json({ message: "invalid loadout" });
      }

      const newLoadout = normalizeLoadout(incoming, me.loadout);
      if (!pgPool) {
        me.displayName = nextName;
        me.loadout = newLoadout;
        me.profileSetupCompleted = true;
      }
      await persistPG(async () => {
        await DB.updateUser(pgPool, uid, { displayName: nextName, loadout: newLoadout, profileSetupCompleted: true });
      });
      const updated = await getUser(uid);
      return res.status(200).json(await profileDTOForViewerAsync(updated, true, true));
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.get("/v1/profile/:userID", profileReadRateLimiter, async (req, res) => {
    try {
      const viewerID = parseBearer(req);
      const targetID = String(req.params.userID || "").trim();
      if (!targetID || targetID === "me") {
        const me = await getUser(viewerID);
        if (!me) return res.status(404).json({ message: "user not found" });
        return res.status(200).json(await profileDTOForViewerAsync(me, true, true));
      }

      const viewer = await getUser(viewerID);
      const target = await getUser(targetID);
      if (!viewer || !target) return res.status(404).json({ message: "user not found" });

      if (await isBlockedEitherDirectionSafe(viewerID, targetID)) {
        return res.status(404).json({ message: "user not found" });
      }

      const isSelf = viewerID === targetID;
      const isFriend = await checkAreFriends(viewerID, targetID);
      return res.status(200).json(await profileDTOForViewerAsync(target, isSelf, isFriend));
    } catch (err) {
      if (err?.message !== "missing bearer" && err?.message !== "invalid token") console.error(`[ERROR] ${req.method} ${req.originalUrl}:`, err);
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/media/upload", uploadRateLimiter, rejectWhenWriteFrozen, upload.single("file"), async (req, res) => {
    const requestStartedAt = timingNowNs();
    try {
      const uid = parseBearer(req);
      const mediaUser = await getUser(uid);
      if (!mediaUser) return res.status(404).json({ message: "user not found" });
      if (!req.file || !req.file.buffer) return res.status(400).json({ message: "file required" });

      const ext = safeExt(req.file.originalname);
      const contentHash = crypto.createHash("md5").update(req.file.buffer).digest("hex");
      const objectKey = `${uid}/${contentHash}${ext}`;

      // Content-hash dedup: if the exact same file already exists, return immediately.
      const fullPath = path.join(MEDIA_DIR, objectKey);
      const base = derivePublicBase(req);
      const url = base ? `${base}/media/${objectKey}` : `/media/${objectKey}`;
      try {
        await fsp.access(fullPath);
        // File exists — skip write, return existing URL.
        logTiming("media_upload", {
          userID: uid,
          backend: "dedup",
          bytes: req.file.buffer.length,
          writeDurationMs: 0,
          totalDurationMs: elapsedMs(requestStartedAt)
        });
        return res.status(200).json({ objectKey, url });
      } catch {
        // File does not exist — proceed with write.
      }

      // Always write to local disk first (fast, reliable)
      const diskWriteStartedAt = timingNowNs();
      await fsp.mkdir(path.dirname(fullPath), { recursive: true });
      await fsp.writeFile(fullPath, req.file.buffer);
      const fileBytes = req.file.buffer.length;
      const fileMime = req.file.mimetype;
      logTiming("media_upload", {
        userID: uid,
        backend: "disk",
        bytes: fileBytes,
        writeDurationMs: elapsedMs(diskWriteStartedAt),
        totalDurationMs: elapsedMs(requestStartedAt)
      });

      // Async sync to R2 in background (non-blocking)
      if (r2Client) {
        setImmediate(async () => {
          try {
            const buf = await fsp.readFile(fullPath);
            await uploadToR2OrThrow(objectKey, buf, fileMime);
            logTiming("media_r2_sync", { userID: uid, objectKey, bytes: fileBytes, status: "ok" });
          } catch (e) {
            logTiming("media_r2_sync", { userID: uid, objectKey, bytes: fileBytes, status: "failed", message: e && e.message ? e.message : String(e) });
          }
        });
      }

      // Warm Cloudflare CDN cache so first viewer gets a HIT instead of slow origin fetch
      if (url.startsWith("http")) {
        setImmediate(() => {
          fetch(url).catch(() => {});
        });
      }

      return res.status(200).json({ objectKey, url });
    } catch (error) {
      logTiming("media_upload_error", {
        totalDurationMs: elapsedMs(requestStartedAt),
        message: error && error.message ? error.message : "unauthorized"
      });
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.use((err, _req, res, _next) => {
    if (err && (err.type === "entity.too.large" || err.status === 413)) {
      return res.status(413).json({ message: "payload too large" });
    }
    if (err instanceof multer.MulterError && err.code === "LIMIT_FILE_SIZE") {
      return res.status(413).json({ message: "payload too large" });
    }
    if (err) {
      console.error("request error:", err && err.message ? err.message : err);
    }
    return res.status(500).json({ message: "internal error" });
  });

  const server = app.listen(PORT, () => {
    console.log(`[streetstamps-node-v1] listening on :${PORT}`);
    const memoryTimer = setInterval(() => {
      const mem = process.memoryUsage();
      console.log(`[memory] rss=${(mem.rss/1024/1024).toFixed(0)}MB heap=${(mem.heapUsed/1024/1024).toFixed(0)}MB`);
      if (mem.heapUsed > 1500 * 1024 * 1024) {
        console.warn('[memory] high memory usage detected');
      }
    }, 60000);

    let shutdownStarted = false;
    const gracefulShutdown = (signal) => {
      if (shutdownStarted) return;
      shutdownStarted = true;
      console.log(`[shutdown] ${signal} received, draining connections...`);
      clearInterval(memoryTimer);
      server.close(async () => {
        console.log("[shutdown] HTTP server closed");
        try {
          if (pgPool) {
            await pgPool.end();
            console.log("[shutdown] PostgreSQL pool closed");
          }
        } catch (e) {
          console.error("[shutdown] pool close error:", e.message);
        }
        process.exit(0);
      });
      // Force exit after 15s if connections don't drain
      setTimeout(() => {
        console.error("[shutdown] forced exit after timeout");
        process.exit(1);
      }, 15000).unref();
    };
    process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));
    process.on("SIGINT", () => gracefulShutdown("SIGINT"));
  });
}

main().catch((e) => {
  console.error("fatal:", e);
  process.exit(1);
});
