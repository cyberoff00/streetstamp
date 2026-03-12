import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { spawn } from "node:child_process";

const SERVER_DIR = process.cwd();
let nextPort = 18320;

function emptyState() {
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

async function waitForHealth(port, getLogs) {
  const start = Date.now();
  while (Date.now() - start < 8000) {
    try {
      const resp = await fetch(`http://127.0.0.1:${port}/v1/health`);
      if (resp.ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 120));
  }
  const logs = typeof getLogs === "function" ? getLogs() : "";
  throw new Error(`server did not become healthy${logs ? `\n${logs}` : ""}`);
}

async function stopServer(child) {
  if (!child) return;
  if (child.exitCode !== null || child.signalCode !== null) return;
  child.kill("SIGTERM");
  await new Promise((resolve) => child.once("close", resolve));
}

async function startServer(t, env = {}) {
  const port = nextPort;
  nextPort += 1;

  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "security-hardening-"));
  const dataFile = path.join(tmp, "data.json");
  const mediaDir = path.join(tmp, "media");
  await fs.writeFile(dataFile, JSON.stringify(emptyState(), null, 2), "utf8");
  await fs.mkdir(mediaDir, { recursive: true });

  const child = spawn("node", ["server.js"], {
    cwd: SERVER_DIR,
    env: {
      ...process.env,
      PORT: String(port),
      DATA_FILE: dataFile,
      MEDIA_DIR: mediaDir,
      MEDIA_PUBLIC_BASE: `http://127.0.0.1:${port}`,
      DATABASE_URL: "",
      ...env
    },
    stdio: ["ignore", "pipe", "pipe"]
  });

  let logs = "";
  child.stdout?.on("data", (chunk) => {
    logs += String(chunk);
  });
  child.stderr?.on("data", (chunk) => {
    logs += String(chunk);
  });

  t.after(async () => {
    await stopServer(child);
    await fs.rm(tmp, { recursive: true, force: true });
  });

  await waitForHealth(port, () => logs);
  return { port };
}

test("health responses expose security headers and allow configured origins", async (t) => {
  const { port } = await startServer(t, {
    CORS_ALLOWED_ORIGINS: "https://app.streetstamps.cyberkkk.cn,https://streetstamps.cyberkkk.cn"
  });

  const resp = await fetch(`http://127.0.0.1:${port}/v1/health`, {
    headers: {
      Origin: "https://app.streetstamps.cyberkkk.cn"
    }
  });

  assert.equal(resp.status, 200);
  assert.equal(resp.headers.get("access-control-allow-origin"), "https://app.streetstamps.cyberkkk.cn");
  assert.equal(resp.headers.get("x-content-type-options"), "nosniff");
  assert.equal(resp.headers.get("x-frame-options"), "DENY");
  assert.equal(resp.headers.get("referrer-policy"), "same-origin");
  assert.equal(resp.headers.get("x-powered-by"), null);
});

test("disallowed origins are rejected before route handling", async (t) => {
  const { port } = await startServer(t, {
    CORS_ALLOWED_ORIGINS: "https://app.streetstamps.cyberkkk.cn"
  });

  const resp = await fetch(`http://127.0.0.1:${port}/v1/health`, {
    headers: {
      Origin: "https://evil.example.com"
    }
  });

  assert.equal(resp.status, 403);
  const data = await resp.json();
  assert.equal(data.message, "origin not allowed");
});

test("auth endpoints are rate limited", async (t) => {
  const { port } = await startServer(t, {
    AUTH_RATE_LIMIT_MAX: "3",
    AUTH_RATE_LIMIT_WINDOW_MS: "60000"
  });

  for (let i = 0; i < 3; i += 1) {
    const resp = await fetch(`http://127.0.0.1:${port}/v1/auth/login`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "nobody@example.com", password: "Password1!" })
    });
    assert.notEqual(resp.status, 429);
  }

  const throttled = await fetch(`http://127.0.0.1:${port}/v1/auth/login`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email: "nobody@example.com", password: "Password1!" })
  });
  const data = await throttled.json();

  assert.equal(throttled.status, 429);
  assert.equal(data.message, "too many requests");
});

test("oversized json bodies return 413", async (t) => {
  const { port } = await startServer(t, {
    JSON_BODY_LIMIT_MB: "1"
  });

  const oversized = "x".repeat(1_200_000);
  const resp = await fetch(`http://127.0.0.1:${port}/v1/auth/register`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email: "big@example.com", password: oversized })
  });

  const data = await resp.json();
  assert.equal(resp.status, 413);
  assert.equal(data.message, "payload too large");
});

test("legacy email auth endpoints are disabled", async (t) => {
  const { port } = await startServer(t, {});

  const registerResp = await fetch(`http://127.0.0.1:${port}/v1/auth/email/register`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email: "legacy@example.com", password: "Password1!" })
  });
  assert.equal(registerResp.status, 410);
  const registerData = await registerResp.json();
  assert.equal(registerData.code, "legacy_auth_endpoint_disabled");

  const loginResp = await fetch(`http://127.0.0.1:${port}/v1/auth/email/login`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email: "legacy@example.com", password: "Password1!" })
  });
  assert.equal(loginResp.status, 410);
  const loginData = await loginResp.json();
  assert.equal(loginData.code, "legacy_auth_endpoint_disabled");
});

test("production rejects weak jwt secret defaults at startup", async () => {
  const port = nextPort;
  nextPort += 1;
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "security-hardening-jwt-"));
  const dataFile = path.join(tmp, "data.json");
  const mediaDir = path.join(tmp, "media");
  await fs.writeFile(dataFile, JSON.stringify(emptyState(), null, 2), "utf8");
  await fs.mkdir(mediaDir, { recursive: true });

  const child = spawn("node", ["server.js"], {
    cwd: SERVER_DIR,
    env: {
      ...process.env,
      NODE_ENV: "production",
      PORT: String(port),
      JWT_SECRET: "change-me-in-production",
      DATA_FILE: dataFile,
      MEDIA_DIR: mediaDir,
      DATABASE_URL: ""
    },
    stdio: ["ignore", "pipe", "pipe"]
  });

  let logs = "";
  child.stdout?.on("data", (chunk) => {
    logs += String(chunk);
  });
  child.stderr?.on("data", (chunk) => {
    logs += String(chunk);
  });

  const exitCode = await new Promise((resolve) => child.once("close", resolve));
  await fs.rm(tmp, { recursive: true, force: true });

  assert.notEqual(exitCode, 0);
  assert.match(logs, /weak jwt_secret/i);
});
