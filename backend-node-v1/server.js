const fs = require("fs");
const fsp = require("fs/promises");
const path = require("path");
const crypto = require("crypto");
const express = require("express");
const cors = require("cors");
const jwt = require("jsonwebtoken");
const multer = require("multer");
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
const JSON_BODY_LIMIT_MB = Number(process.env.JSON_BODY_LIMIT_MB || 6);
const MEDIA_UPLOAD_MAX_BYTES = Number(process.env.MEDIA_UPLOAD_MAX_BYTES || 10 * 1024 * 1024);
const CORS_ALLOWED_ORIGINS = String(process.env.CORS_ALLOWED_ORIGINS || "").trim();
const AUTH_RATE_LIMIT_WINDOW_MS = Number(process.env.AUTH_RATE_LIMIT_WINDOW_MS || 15 * 60 * 1000);
const AUTH_RATE_LIMIT_MAX = Number(process.env.AUTH_RATE_LIMIT_MAX || 20);
const AUTH_LOGIN_RATE_LIMIT_WINDOW_MS = Number(process.env.AUTH_LOGIN_RATE_LIMIT_WINDOW_MS || AUTH_RATE_LIMIT_WINDOW_MS);
const AUTH_LOGIN_RATE_LIMIT_MAX = Number(process.env.AUTH_LOGIN_RATE_LIMIT_MAX || AUTH_RATE_LIMIT_MAX);
const AUTH_REFRESH_RATE_LIMIT_WINDOW_MS = Number(process.env.AUTH_REFRESH_RATE_LIMIT_WINDOW_MS || 5 * 60 * 1000);
const AUTH_REFRESH_RATE_LIMIT_MAX = Number(process.env.AUTH_REFRESH_RATE_LIMIT_MAX || 80);
const WRITE_RATE_LIMIT_WINDOW_MS = Number(process.env.WRITE_RATE_LIMIT_WINDOW_MS || 60 * 1000);
const WRITE_RATE_LIMIT_MAX = Number(process.env.WRITE_RATE_LIMIT_MAX || 40);
const UPLOAD_RATE_LIMIT_WINDOW_MS = Number(process.env.UPLOAD_RATE_LIMIT_WINDOW_MS || 60 * 1000);
const UPLOAD_RATE_LIMIT_MAX = Number(process.env.UPLOAD_RATE_LIMIT_MAX || 10);
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
const R2_PUBLIC_BASE = (process.env.R2_PUBLIC_BASE || "").trim();
const GOOGLE_CLIENT_ID = (process.env.GOOGLE_CLIENT_ID || "").trim();
const APPLE_AUDIENCES = (process.env.APPLE_AUDIENCES || process.env.APPLE_BUNDLE_ID || "").trim();
const APPSTORE_FALLBACK_URL = (process.env.APPSTORE_FALLBACK_URL || "https://apps.apple.com/us/search?term=StreetStamps").trim();
const FIREBASE_AUTH_ENABLED = String(process.env.FIREBASE_AUTH_ENABLED || "").trim().toLowerCase();
const FIREBASE_PROJECT_ID = (process.env.FIREBASE_PROJECT_ID || "").trim();
const FIREBASE_SERVICE_ACCOUNT_PATH = (process.env.GOOGLE_APPLICATION_CREDENTIALS || process.env.FIREBASE_SERVICE_ACCOUNT_PATH || "").trim();
const FIREBASE_SERVICE_ACCOUNT_JSON = (process.env.FIREBASE_SERVICE_ACCOUNT_JSON || "").trim();
const FIREBASE_LEGACY_EMAIL = normalizeEmail(process.env.FIREBASE_LEGACY_EMAIL || "yinterestingy@gmail.com");
const FIREBASE_LEGACY_APP_USER_ID = (process.env.FIREBASE_LEGACY_APP_USER_ID || "").trim();

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
const rawFirebaseFixtures = process.env.TEST_FIREBASE_AUTH_FIXTURES || "{}";
let firebaseAuthFixtures = {};
try {
  firebaseAuthFixtures = JSON.parse(rawFirebaseFixtures);
} catch {
  firebaseAuthFixtures = {};
}
let firebaseAdminAuthPromise = null;

function normalizeEmail(raw) {
  const email = String(raw || "").trim().toLowerCase();
  return email.includes("@") ? email : "";
}

function firebaseAuthEnabled() {
  return FIREBASE_AUTH_ENABLED === "1" || FIREBASE_AUTH_ENABLED === "true" || FIREBASE_AUTH_ENABLED === "yes";
}

function parseTruthy(raw) {
  if (typeof raw === "boolean") return raw;
  const value = String(raw || "").trim().toLowerCase();
  return value === "true" || value === "1";
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

function firebaseAuthConfigError() {
  if (!firebaseAuthEnabled()) return "";
  if (!FIREBASE_PROJECT_ID) {
    return "firebase auth enabled but FIREBASE_PROJECT_ID is missing";
  }
  if (!FIREBASE_SERVICE_ACCOUNT_PATH && !FIREBASE_SERVICE_ACCOUNT_JSON) {
    return "firebase auth enabled but GOOGLE_APPLICATION_CREDENTIALS or FIREBASE_SERVICE_ACCOUNT_JSON is missing";
  }
  if (!FIREBASE_LEGACY_EMAIL) {
    return "firebase auth enabled but FIREBASE_LEGACY_EMAIL is missing";
  }
  if (!FIREBASE_LEGACY_APP_USER_ID) {
    return "firebase auth enabled but FIREBASE_LEGACY_APP_USER_ID is missing";
  }
  return "";
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

function firebaseFixturePayload(idToken) {
  const token = String(idToken || "").trim();
  if (!token) return null;
  const payload = firebaseAuthFixtures[token];
  return payload && typeof payload === "object" ? payload : null;
}

async function firebaseAdminAuth() {
  if (firebaseAdminAuthPromise) return firebaseAdminAuthPromise;
  firebaseAdminAuthPromise = (async () => {
    let initializeApp;
    let getApps;
    let cert;
    let applicationDefault;
    let getAuth;
    try {
      ({ initializeApp, getApps, cert, applicationDefault } = require("firebase-admin/app"));
      ({ getAuth } = require("firebase-admin/auth"));
    } catch {
      throw new Error("firebase-admin not installed");
    }

    if (!getApps().length) {
      const options = { projectId: FIREBASE_PROJECT_ID };
      if (FIREBASE_SERVICE_ACCOUNT_JSON) {
        options.credential = cert(JSON.parse(FIREBASE_SERVICE_ACCOUNT_JSON));
      } else {
        if (FIREBASE_SERVICE_ACCOUNT_PATH && !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
          process.env.GOOGLE_APPLICATION_CREDENTIALS = FIREBASE_SERVICE_ACCOUNT_PATH;
        }
        options.credential = applicationDefault();
      }
      initializeApp(options);
    }

    return getAuth();
  })();
  return firebaseAdminAuthPromise;
}

function firebaseIdentityFromClaims(rawClaims) {
  const claims = rawClaims && typeof rawClaims === "object" ? rawClaims : {};
  const uid = String(claims.uid || claims.user_id || claims.sub || "").trim();
  if (!uid) throw new Error("invalid firebase token uid");

  const providerCandidates = [];
  if (typeof claims.firebase?.sign_in_provider === "string") {
    providerCandidates.push(claims.firebase.sign_in_provider);
  }
  if (typeof claims.provider_id === "string") {
    providerCandidates.push(claims.provider_id);
  }
  if (Array.isArray(claims.providers)) {
    providerCandidates.push(...claims.providers);
  }

  return {
    uid,
    email: normalizeEmail(claims.email),
    emailVerified: parseTruthy(claims.email_verified),
    providers: Array.from(new Set(
      providerCandidates
        .map((value) => String(value || "").trim())
        .filter(Boolean)
    ))
  };
}

async function verifyFirebaseIdentityToken(idToken) {
  const fixture = firebaseFixturePayload(idToken);
  if (fixture) {
    return firebaseIdentityFromClaims(fixture);
  }
  if (!firebaseAuthEnabled()) {
    throw new Error("firebase auth disabled");
  }

  const auth = await firebaseAdminAuth();
  const decoded = await auth.verifyIdToken(String(idToken || "").trim());
  return firebaseIdentityFromClaims(decoded);
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

function hashPassword(pw) {
  return hashSHA256(`StreetStamps::${pw}`);
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
  await saveDB();
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

function issueEmailVerificationToken(userID, email) {
  const rawToken = randHex(24);
  const tokenID = `evt_${randHex(12)}`;
  db.emailVerificationTokens[tokenID] = {
    id: tokenID,
    userID,
    email,
    tokenHash: hashSHA256(rawToken),
    expiresAt: emailVerificationExpiresAt(),
    usedAt: null,
    createdAt: nowUnix()
  };
  return rawToken;
}

function issuePasswordResetToken(userID, email) {
  const rawToken = randHex(24);
  const tokenID = `prt_${randHex(12)}`;
  db.passwordResetTokens[tokenID] = {
    id: tokenID,
    userID,
    email,
    tokenHash: hashSHA256(rawToken),
    expiresAt: emailVerificationExpiresAt(),
    usedAt: null,
    createdAt: nowUnix()
  };
  return rawToken;
}

function revokeRefreshTokensForUser(userID) {
  const revokedAt = nowUnix();
  for (const record of Object.values(db.refreshTokens || {})) {
    if (record.userID === userID && !record.revokedAt) {
      record.revokedAt = revokedAt;
    }
  }
}

function issueStoredRefreshToken(userID, provider, deviceInfo = null) {
  const rawToken = makeRefreshToken(userID, provider);
  const tokenID = `rft_${randHex(12)}`;
  db.refreshTokens[tokenID] = {
    id: tokenID,
    userID,
    tokenHash: hashSHA256(rawToken),
    deviceInfo: deviceInfo || null,
    expiresAt: nowUnix() + (30 * 24 * 60 * 60),
    revokedAt: null,
    createdAt: nowUnix()
  };
  return rawToken;
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
  const excluded = String(excludedUserID || "").trim();
  for (const [uid, user] of Object.entries(db.users || {})) {
    if (uid === excluded) continue;
    if (baseDisplayName(user?.displayName) === next) {
      return false;
    }
  }
  return true;
}

function allocateUniqueDisplayName(displayName, excludedUserID = "") {
  const base = baseDisplayName(displayName);
  if (canUseDisplayName(base, excludedUserID)) return base;
  let suffix = 2;
  while (suffix < 1000000) {
    const candidate = `${base}${suffix}`;
    if (canUseDisplayName(candidate, excludedUserID)) return candidate;
    suffix += 1;
  }
  return `${base}${nowUnix()}`;
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
  }

  return changed;
}

function ensureProfileSetupCompleted(user, defaultValue) {
  if (!user || typeof user !== "object") return false;
  if (typeof user.profileSetupCompleted === "boolean") return false;
  user.profileSetupCompleted = Boolean(defaultValue);
  return true;
}

function authSuccessPayload(user, provider, email, accessToken, refreshToken) {
  return {
    userId: user.id,
    provider,
    email: email || null,
    accessToken,
    refreshToken,
    needsProfileSetup: !Boolean(user.profileSetupCompleted)
  };
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

function normalizeCityCardPayload(raw) {
  const id = String(raw?.id || "").trim();
  if (!id) return null;
  return {
    id,
    name: String(raw?.name || id).trim() || id,
    countryISO2: raw?.countryISO2 == null ? null : String(raw.countryISO2 || "").trim() || null
  };
}

function mergeJourneyPayloads(existingJourneys, incomingJourneys, removedJourneyIDs, snapshotComplete) {
  const normalizedIncoming = (incomingJourneys || []).map(normalizeJourneyPayload);
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

  return out;
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

function appProviderFromFirebaseProviders(providers) {
  const items = Array.isArray(providers) ? providers : [];
  if (items.includes("password")) return "email";
  if (items.includes("google.com")) return "google";
  if (items.includes("apple.com")) return "apple";
  return "firebase";
}

function createFirebaseBackedUser(identity) {
  const uid = `u_${randHex(12)}`;
  const invite = genInviteCode();
  db.users[uid] = {
    id: uid,
    provider: appProviderFromFirebaseProviders(identity.providers),
    email: identity.email || null,
    passwordHash: null,
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
  setUserHandle(uid, null, { strict: false });
  db.inviteIndex[invite] = uid;
  return uid;
}

function upsertFirebaseIdentityIndex(identity, appUserId) {
  const now = new Date().toISOString();
  const existing = db.firebaseIdentityIndex?.[identity.uid];
  const next = {
    firebaseUid: identity.uid,
    appUserId,
    email: identity.email || null,
    emailVerified: Boolean(identity.emailVerified),
    providers: Array.isArray(identity.providers) ? identity.providers : [],
    createdAt: existing?.createdAt || now,
    lastLoginAt: now
  };
  const prevSerialized = JSON.stringify(existing || null);
  const nextSerialized = JSON.stringify(next);
  if (!db.firebaseIdentityIndex || typeof db.firebaseIdentityIndex !== "object") {
    db.firebaseIdentityIndex = {};
  }
  db.firebaseIdentityIndex[identity.uid] = next;
  return prevSerialized !== nextSerialized;
}

function syncFirebaseIdentityEmail(identity, uid) {
  if (!identity.email || !identity.emailVerified) return false;
  const user = db.users[uid];
  if (!user) return false;

  const currentEmailUID = existingUserID(db.emailIndex[identity.email]);
  let changed = false;
  if ((!currentEmailUID || currentEmailUID === uid) && user.email !== identity.email) {
    user.email = identity.email;
    changed = true;
  }
  if ((!currentEmailUID || currentEmailUID === uid) && db.emailIndex[identity.email] !== uid) {
    db.emailIndex[identity.email] = uid;
    changed = true;
  }
  return changed;
}

async function resolveFirebaseBearerUserID(idToken) {
  const identity = await verifyFirebaseIdentityToken(idToken);
  let uid = existingUserID(db.firebaseIdentityIndex?.[identity.uid]?.appUserId);
  let changed = false;

  if (!uid && identity.email && identity.emailVerified && identity.email === FIREBASE_LEGACY_EMAIL) {
    uid = existingUserID(FIREBASE_LEGACY_APP_USER_ID);
    if (!uid) {
      throw new Error("preserved legacy app user missing");
    }
  }

  if (!uid && identity.email && identity.emailVerified) {
    uid = existingUserID(db.emailIndex[identity.email]);
  }

  if (!uid) {
    uid = createFirebaseBackedUser(identity);
    changed = true;
  }

  changed = syncFirebaseIdentityEmail(identity, uid) || changed;
  changed = upsertFirebaseIdentityIndex(identity, uid) || changed;

  if (changed) {
    await saveDB();
  }

  return uid;
}

async function resolveBearerUserID(token) {
  try {
    return parseLegacyAccessToken(token);
  } catch {}
  return resolveFirebaseBearerUserID(token);
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
  return jwt.sign({ uid, prv: provider, typ: "access", sid: randHex(8) }, JWT_SECRET, { expiresIn: "2h" });
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
    firebaseIdentityIndex: {},
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
    firebaseIdentityIndex: parsed?.firebaseIdentityIndex || {},
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

function hasPersistedData(parsed) {
  const src = parsed || {};
  const keys = [
    "users",
    "emailIndex",
    "inviteIndex",
    "oauthIndex",
    "firebaseIdentityIndex",
    "authIdentities",
    "emailVerificationTokens",
    "passwordResetTokens",
    "refreshTokens",
    "handleIndex",
    "likesIndex",
    "friendRequestsIndex",
    "postcardsIndex"
  ];
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
    message: `${fromUser.displayName}在你的沙发上坐了一坐`,
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

function pushPostcardReceivedNotification(owner, fromUser, postcard) {
  ensureUserNotifications(owner);
  owner.notifications.unshift({
    id: `n_${randHex(10)}`,
    type: "postcard_received",
    fromUserID: fromUser.id,
    fromDisplayName: fromUser.displayName,
    journeyID: null,
    journeyTitle: null,
    message: `${fromUser.displayName} 给你寄来了一张来自 ${postcard.cityName || postcard.cityID} 的明信片`,
    createdAt: new Date().toISOString(),
    read: false,
    postcardMessageID: postcard.messageID,
    cityID: postcard.cityID,
    cityName: postcard.cityName || postcard.cityID,
    photoURL: postcard.photoURL || null,
    messageText: postcard.messageText || ""
  });
  if (owner.notifications.length > 400) {
    owner.notifications = owner.notifications.slice(0, 400);
  }
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
    profileSetupCompleted: Boolean(target.profileSetupCompleted),
    email: isSelf ? (target.email || null) : null,
    bio: target.bio,
    loadout: normalizeLoadout(target.loadout),
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
  const prodConfigError = productionConfigError();
  if (prodConfigError) {
    throw new Error(prodConfigError);
  }
  const firebaseConfigError = firebaseAuthConfigError();
  if (firebaseConfigError) {
    throw new Error(firebaseConfigError);
  }
  db = await loadDB();
  console.log(`[streetstamps-node-v1] storage=${pgPool ? "postgresql" : "file"}`);
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
  app.use(express.json({
    limit: `${Number.isFinite(JSON_BODY_LIMIT_MB) && JSON_BODY_LIMIT_MB > 0 ? JSON_BODY_LIMIT_MB : 6}mb`
  }));
  app.use("/media", express.static(MEDIA_DIR));
  app.use(async (req, _res, next) => {
    const header = String(req.headers.authorization || "");
    if (!header.startsWith("Bearer ")) {
      return next();
    }
    try {
      req.authUserID = await resolveBearerUserID(header.slice(7).trim());
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
    media: {
      maxUploadBytes: Number.isFinite(MEDIA_UPLOAD_MAX_BYTES) && MEDIA_UPLOAD_MAX_BYTES > 0
        ? MEDIA_UPLOAD_MAX_BYTES
        : 10 * 1024 * 1024,
      objectStorage: Boolean(r2Client)
    }
  }));

  app.post("/v1/auth/register", authRateLimiter, async (req, res) => {
    try {
      const email = String(req.body?.email || "").trim().toLowerCase();
      const password = String(req.body?.password || "");
      const displayName = String(req.body?.displayName || "").trim();
      if (!email.includes("@")) return res.status(400).json({ message: "invalid email" });
      if (!isStrongPassword(password)) {
        return res.status(400).json({ message: "password must be at least 8 characters and include a letter, number, and special character" });
      }
      if (db.emailIndex[email]) return res.status(409).json({ message: "email already exists" });

      const uid = `u_${randHex(12)}`;
      const invite = genInviteCode();
      const passwordHash = hashPassword(password);
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
      db.users[uid] = user;
      setUserHandle(uid, null, { strict: false });
      db.emailIndex[email] = uid;
      db.inviteIndex[invite] = uid;
      const identityID = `aid_${randHex(12)}`;
      db.authIdentities[identityID] = {
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
      const verificationToken = issueEmailVerificationToken(uid, email);
      await saveDB();
      await deliverVerificationEmail(email, verificationToken);

      return res.status(200).json({
        userId: uid,
        email,
        emailVerificationRequired: true,
        needsProfileSetup: true
      });
    } catch {
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.post("/v1/auth/verify-email", authRateLimiter, async (req, res) => {
    try {
      const result = await consumeEmailVerificationToken(req.body?.token);
      if (!result.ok) return res.status(result.status).json({ message: result.message });
      return res.status(200).json({ ok: true, email: result.email });
    } catch {
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.get("/verify-email", async (req, res) => {
    try {
      applyHTMLSecurityHeaders(res);
      const result = await consumeEmailVerificationToken(req.query?.token);
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
    } catch {
      res.status(500);
      res.type("html");
      return res.send(renderEmailVerificationHTML({
        ok: false,
        title: "Verification link failed",
        body: "We could not verify your email right now."
      }));
    }
  });

  app.get("/reset-password", (req, res) => {
    try {
      applyHTMLSecurityHeaders(res);
      const result = inspectPasswordResetToken(req.query?.token);
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
    } catch {
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

      const identity = Object.values(db.authIdentities || {}).find((item) => (
        item.provider === "email_password" && item.email === email
      ));
      if (!identity || parseTruthy(identity.emailVerified)) {
        return res.status(200).json({ ok: true });
      }

      const token = issueEmailVerificationToken(identity.userID, email);
      await saveDB();
      await deliverVerificationEmail(email, token);
      return res.status(200).json({ ok: true });
    } catch {
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.post("/v1/auth/login", authLoginRateLimiter, async (req, res) => {
    try {
      const email = String(req.body?.email || "").trim().toLowerCase();
      const password = String(req.body?.password || "");
      const identity = Object.values(db.authIdentities || {}).find((item) => (
        item.provider === "email_password" && item.email === email
      ));
      if (!identity) return res.status(404).json({ message: "account not found" });
      if (identity.passwordHash !== hashPassword(password)) return res.status(401).json({ message: "wrong email or password" });
      if (!identity.emailVerified) return res.status(403).json({ message: "email not verified" });

      const user = db.users[identity.userID];
      if (!user) return res.status(404).json({ message: "account not found" });

      const accessToken = makeAccessToken(user.id, user.provider || "email");
      const refreshToken = issueStoredRefreshToken(user.id, user.provider || "email");
      await saveDB();
      return res.status(200).json(authSuccessPayload(
        user,
        user.provider || "email",
        user.email || identity.email || null,
        accessToken,
        refreshToken
      ));
    } catch {
      return res.status(500).json({ message: "internal error" });
    }
  });

  app.post("/v1/auth/refresh", authRefreshRateLimiter, async (req, res) => {
    try {
      const rawToken = String(req.body?.refreshToken || "").trim();
      const payload = parseRefreshToken(rawToken);
      const record = findRefreshTokenRecord(rawToken);
      if (!record || record.revokedAt) return res.status(401).json({ message: "refresh token invalid" });
      if (Number(record.expiresAt || 0) < nowUnix()) return res.status(401).json({ message: "refresh token expired" });

      const user = db.users[payload.uid];
      if (!user) return res.status(401).json({ message: "account not found" });

      return res.status(200).json({
        accessToken: makeAccessToken(user.id, user.provider || payload.prv || "email")
      });
    } catch {
      return res.status(401).json({ message: "refresh token invalid" });
    }
  });

  app.post("/v1/auth/logout", authRateLimiter, async (req, res) => {
    try {
      const rawToken = String(req.body?.refreshToken || "").trim();
      if (!rawToken) return res.status(400).json({ message: "refresh token required" });
      parseRefreshToken(rawToken);
      const record = findRefreshTokenRecord(rawToken);
      if (!record) return res.status(401).json({ message: "refresh token invalid" });
      if (!record.revokedAt) {
        record.revokedAt = nowUnix();
        await saveDB();
      }
      return res.status(200).json({ ok: true });
    } catch {
      return res.status(401).json({ message: "refresh token invalid" });
    }
  });

  app.post("/v1/auth/forgot-password", authRateLimiter, async (req, res) => {
    try {
      const email = String(req.body?.email || "").trim().toLowerCase();
      if (!email.includes("@")) {
        return res.status(200).json({ ok: true });
      }
      const identity = Object.values(db.authIdentities || {}).find((item) => (
        item.provider === "email_password" && item.email === email
      ));
      if (identity) {
        const token = issuePasswordResetToken(identity.userID, email);
        await saveDB();
        await deliverPasswordResetEmail(email, token);
      }
      return res.status(200).json({ ok: true });
    } catch {
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

      const tokenHash = hashSHA256(rawToken);
      const tokenRecord = Object.values(db.passwordResetTokens || {}).find((item) => item.tokenHash === tokenHash);
      if (!tokenRecord) return res.status(400).json({ message: "invalid token" });
      if (tokenRecord.usedAt) return res.status(400).json({ message: "token already used" });
      if (Number(tokenRecord.expiresAt || 0) < nowUnix()) return res.status(400).json({ message: "token expired" });

      const identity = Object.values(db.authIdentities || {}).find((item) => (
        item.provider === "email_password"
          && item.userID === tokenRecord.userID
          && item.email === tokenRecord.email
      ));
      if (!identity) return res.status(400).json({ message: "identity not found" });

      const nextHash = hashPassword(newPassword);
      identity.passwordHash = nextHash;
      identity.updatedAt = nowUnix();
      const user = db.users[tokenRecord.userID];
      if (user) user.passwordHash = nextHash;
      tokenRecord.usedAt = nowUnix();
      revokeRefreshTokensForUser(tokenRecord.userID);
      await saveDB();
      return res.status(200).json({ ok: true });
    } catch {
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
      const existingAppleIdentity = findAuthIdentityByProviderSubject("apple", identity.subject);
      const relayEmail = isApplePrivateRelayEmail(identity.email);
      const verifiedEmailIdentity = identity.email && identity.emailVerified && !relayEmail
        ? findVerifiedEmailPasswordIdentity(identity.email)
        : null;

      const modernUID = existingUserID(existingAppleIdentity?.userID || db.oauthIndex[modernKey]);
      const legacyUID = existingUserID(db.oauthIndex[legacyKey]);
      const emailUID = existingUserID(verifiedEmailIdentity?.userID);

      let uid = chooseCanonicalOAuthUserID([
        { uid: modernUID, source: "modern" },
        { uid: legacyUID, source: "legacy" },
        { uid: emailUID, source: "email" }
      ]);
      let changed = false;

      if (modernUID && modernUID !== uid && mergeEmptyOAuthAccountInto(modernUID, uid)) {
        changed = true;
      }
      if (legacyUID && legacyUID !== uid && mergeEmptyOAuthAccountInto(legacyUID, uid)) {
        changed = true;
      }
      if (emailUID && emailUID !== uid && mergeEmptyOAuthAccountInto(emailUID, uid)) {
        changed = true;
      }

      if (!uid) {
        const user = createDefaultUser("apple", identity.email);
        uid = user.id;
        changed = true;
      }

      if (!uid) return res.status(500).json({ message: "user not found after apple login" });

      const user = db.users[uid];
      if (!user) return res.status(500).json({ message: "user not found after apple login" });

      if (modernKey && db.oauthIndex[modernKey] !== uid) {
        db.oauthIndex[modernKey] = uid;
        changed = true;
      }

      if (!relayEmail && identity.email && identity.emailVerified) {
        const currentEmailUID = existingUserID(db.emailIndex[identity.email]);
        if (!user.email && (!currentEmailUID || currentEmailUID === uid)) {
          user.email = identity.email;
          changed = true;
        }
        if ((!currentEmailUID || currentEmailUID === uid) && db.emailIndex[identity.email] !== uid) {
          db.emailIndex[identity.email] = uid;
          changed = true;
        }
      } else if (!user.email && identity.email) {
        user.email = identity.email;
        changed = true;
      }

      const appleIdentity = upsertAppleAuthIdentity(uid, identity.subject, identity.email, identity.emailVerified);
      if (appleIdentity.userID !== uid) {
        appleIdentity.userID = uid;
        appleIdentity.updatedAt = nowUnix();
        changed = true;
      } else {
        changed = true;
      }

      const accessToken = makeAccessToken(uid, "apple");
      const refreshToken = issueStoredRefreshToken(uid, "apple");
      await saveDB();

      return res.status(200).json(authSuccessPayload(
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
      const modernUID = existingUserID(db.oauthIndex[modernKey]);
      const legacyUID = existingUserID(db.oauthIndex[legacyKey]);
      const emailUID = identity.email && identity.emailVerified
        ? existingUserID(db.emailIndex[identity.email])
        : "";
      let uid = chooseCanonicalOAuthUserID([
        { uid: modernUID, source: "modern" },
        { uid: legacyUID, source: "legacy" },
        { uid: emailUID, source: "email" }
      ]);
      let changed = false;

      if (modernUID && modernUID !== uid && mergeEmptyOAuthAccountInto(modernUID, uid)) {
        changed = true;
      }
      if (legacyUID && legacyUID !== uid && mergeEmptyOAuthAccountInto(legacyUID, uid)) {
        changed = true;
      }
      if (emailUID && emailUID !== uid && mergeEmptyOAuthAccountInto(emailUID, uid)) {
        changed = true;
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
          sentPostcards: [],
          receivedPostcards: [],
          createdAt: nowUnix()
        };
        setUserHandle(uid, null, { strict: false });
        db.inviteIndex[invite] = uid;
        changed = true;
      }

      if (modernKey && db.oauthIndex[modernKey] !== uid) {
        db.oauthIndex[modernKey] = uid;
        changed = true;
      }

      const u = db.users[uid];
      if (!u) return res.status(500).json({ message: "user not found after oauth login" });

      if (identity.email && identity.emailVerified) {
        const currentEmailUID = existingUserID(db.emailIndex[identity.email]);
        if (!u.email && (!currentEmailUID || currentEmailUID === uid)) {
          u.email = identity.email;
          changed = true;
        }
        if ((!currentEmailUID || currentEmailUID === uid) && db.emailIndex[identity.email] !== uid) {
          db.emailIndex[identity.email] = uid;
          changed = true;
        }
      }

      if (changed) {
        await saveDB();
      }
      return res.status(200).json(authSuccessPayload(
        u,
        u.provider,
        u.email || null,
        makeAccessToken(uid, u.provider),
        makeRefreshToken(uid, u.provider)
      ));
    } catch (e) {
      const message = String(e?.message || "").toLowerCase();
      if (message.includes("token") || message.includes("jwt") || message.includes("audience") || message.includes("issuer")) {
        return res.status(401).json({ message: "invalid oauth token" });
      }
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

  app.post("/v1/friends", writeRateLimiter, async (req, res) => {
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

  app.post("/v1/friends/requests", writeRateLimiter, async (req, res) => {
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
        target = resolveUserByInviteCode(inviteCodeRaw);
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

  app.post("/v1/friends/requests/:requestID/accept", writeRateLimiter, async (req, res) => {
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

  app.post("/v1/friends/requests/:requestID/reject", writeRateLimiter, async (req, res) => {
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

  app.delete("/v1/friends/:friendID", writeRateLimiter, async (req, res) => {
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

  app.post("/v1/journeys/migrate", writeRateLimiter, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });
      const journeys = Array.isArray(req.body?.journeys) ? req.body.journeys : [];
      const unlockedCityCards = Array.isArray(req.body?.unlockedCityCards) ? req.body.unlockedCityCards : [];
      const removedJourneyIDs = Array.isArray(req.body?.removedJourneyIDs) ? req.body.removedJourneyIDs : [];
      const snapshotComplete = parseTruthy(req.body?.snapshotComplete);
      me.journeys = mergeJourneyPayloads(me.journeys || [], journeys, removedJourneyIDs, snapshotComplete);
      me.cityCards = mergeCityCardPayloads(me.cityCards || [], unlockedCityCards, snapshotComplete);
      await saveDB();
      return res.status(200).json({ journeys: me.journeys.length, cityCards: me.cityCards.length });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/journeys/likes/batch", writeRateLimiter, (req, res) => {
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

  app.post("/v1/journeys/:ownerUserID/:journeyID/like", writeRateLimiter, async (req, res) => {
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

  app.delete("/v1/journeys/:ownerUserID/:journeyID/like", writeRateLimiter, async (req, res) => {
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

  app.post("/v1/postcards/send", writeRateLimiter, async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
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
      if (messageText.length > 80) {
        return res.status(400).json({ code: "message_too_long", message: "messageText must be <= 80 chars" });
      }

      const target = resolveUserByAnyID(toUserID);
      if (!target) return res.status(404).json({ message: "target user not found" });
      if (uid === target.id) return res.status(400).json({ message: "cannot send postcard to yourself" });
      if (!isFriendOf(me, target.id)) return res.status(403).json({ message: "friends only" });

      ensurePostcardCollections(me);
      ensurePostcardCollections(target);

      const rule = canSendPostcard({
        sentPostcards: me.sentPostcards,
        toUserID,
        cityID,
        cityJourneyCount,
        clientDraftID,
        allowedCityIDs
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
      const message = {
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
      const canonicalMessage = upsertPostcard(message) || message;

      me.sentPostcards.unshift(canonicalMessage);
      target.receivedPostcards.unshift(canonicalMessage);
      if (me.sentPostcards.length > 1000) me.sentPostcards = me.sentPostcards.slice(0, 1000);
      if (target.receivedPostcards.length > 1000) target.receivedPostcards = target.receivedPostcards.slice(0, 1000);

      pushPostcardReceivedNotification(target, me, canonicalMessage);
      await saveDB();

      return res.status(200).json({
        messageID: canonicalMessage.messageID,
        sentAt: canonicalMessage.sentAt
      });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.get("/v1/postcards", (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });
      ensurePostcardCollections(me);

      const boxRaw = String(req.query?.box || "sent").trim().toLowerCase();
      const box = boxRaw === "received" ? "received" : "sent";
      const source = box === "received" ? (me.receivedPostcards || []) : (me.sentPostcards || []);
      const items = source
        .map((item) => normalizePostcardMessage(item))
        .filter(Boolean)
        .filter((item) => String(item.photoURL || "").trim().length > 0)
        .map((item) => ({
          ...item,
          photoURL: absolutizePostcardPhotoURL(item.photoURL, req)
        }))
        .sort((a, b) => Date.parse(b.sentAt || "") - Date.parse(a.sentAt || ""));
      return res.status(200).json({ items, cursor: null });
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
      const filtered = unreadOnly ? source.filter((x) => !x.read) : source;
      const items = filtered.map((item) => {
        if (!item || item.type !== "postcard_received") return item;
        return {
          ...item,
          photoURL: absolutizePostcardPhotoURL(item.photoURL, req)
        };
      });
      return res.status(200).json({ items });
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/notifications/read", writeRateLimiter, async (req, res) => {
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

  app.post("/v1/profile/:userID/stomp", writeRateLimiter, async (req, res) => {
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
      if (!canUseDisplayName(nextName, uid)) {
        return res.status(409).json({ message: "display name already taken" });
      }

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

      me.loadout = normalizeLoadout(incoming, me.loadout);
      await saveDB();
      return res.status(200).json(profileDTOForViewer(me, true, true));
    } catch {
      return res.status(401).json({ message: "unauthorized" });
    }
  });

  app.post("/v1/profile/setup", async (req, res) => {
    try {
      const uid = parseBearer(req);
      const me = db.users[uid];
      if (!me) return res.status(404).json({ message: "user not found" });

      const nextName = normalizeDisplayName(req.body?.displayName);
      if (!nextName) return res.status(400).json({ message: "invalid display name" });
      if (!canUseDisplayName(nextName, uid)) {
        return res.status(409).json({ message: "display name already taken" });
      }

      const incoming = req.body?.loadout;
      if (!incoming || typeof incoming !== "object" || Array.isArray(incoming)) {
        return res.status(400).json({ message: "invalid loadout" });
      }

      me.displayName = nextName;
      me.loadout = normalizeLoadout(incoming, me.loadout);
      me.profileSetupCompleted = true;
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

  app.post("/v1/media/upload", uploadRateLimiter, upload.single("file"), async (req, res) => {
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
      const base = derivePublicBase(req);
      const url = base ? `${base}/media/${objectKey}` : `/media/${objectKey}`;
      return res.status(200).json({ objectKey, url });
    } catch {
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

  app.listen(PORT, () => {
    console.log(`[streetstamps-node-v1] listening on :${PORT}`);
  });
}

main().catch((e) => {
  console.error("fatal:", e);
  process.exit(1);
});
