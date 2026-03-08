import assert from "node:assert/strict";
import crypto from "node:crypto";
import { spawn } from "node:child_process";
import path from "node:path";
import os from "node:os";
import fs from "node:fs/promises";

const SERVER_DIR = process.cwd();
const PORT = 18231;

function hashSHA256(raw) {
  return crypto.createHash("sha256").update(raw).digest("hex");
}

async function waitForHealth(port) {
  const start = Date.now();
  while (Date.now() - start < 8000) {
    try {
      const resp = await fetch(`http://127.0.0.1:${port}/v1/health`);
      if (resp.ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 120));
  }
  throw new Error("server did not become healthy");
}

function startServer({ port, dataFile, mediaDir, outboxFile }) {
  return spawn("node", ["server.js"], {
    cwd: SERVER_DIR,
    env: {
      ...process.env,
      PORT: String(port),
      DATA_FILE: dataFile,
      MEDIA_DIR: mediaDir,
      MEDIA_PUBLIC_BASE: `http://127.0.0.1:${port}`,
      DATABASE_URL: "",
      TEST_EMAIL_OUTBOX_FILE: outboxFile
    },
    stdio: "ignore"
  });
}

async function stopServer(child) {
  if (!child) return;
  if (child.exitCode !== null || child.signalCode !== null) return;
  child.kill("SIGTERM");
  await new Promise((resolve) => child.once("close", resolve));
}

async function requestJSON(port, method, pathName, body) {
  const resp = await fetch(`http://127.0.0.1:${port}${pathName}`, {
    method,
    headers: { "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined
  });
  const data = await resp.json().catch(() => ({}));
  return { status: resp.status, data };
}

async function readOutbox(outboxFile) {
  try {
    const raw = await fs.readFile(outboxFile, "utf8");
    return JSON.parse(raw);
  } catch (error) {
    if (error && error.code === "ENOENT") return [];
    throw error;
  }
}

function extractToken(verificationURL) {
  const url = new URL(verificationURL);
  return url.searchParams.get("token");
}

async function run() {
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "auth-verify-email-"));
  const dataFile = path.join(tmp, "data.json");
  const mediaDir = path.join(tmp, "media");
  const outboxFile = path.join(tmp, "outbox.json");
  await fs.writeFile(dataFile, JSON.stringify({
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
  }, null, 2), "utf8");

  let child = startServer({ port: PORT, dataFile, mediaDir, outboxFile });

  try {
    await waitForHealth(PORT);

    const created = await requestJSON(PORT, "POST", "/v1/auth/register", {
      email: "verify-me@example.com",
      password: "Password1!"
    });
    assert.equal(created.status, 200);

    const outbox = await readOutbox(outboxFile);
    assert.equal(outbox.length, 1, "expected one verification email");
    const issuedToken = extractToken(outbox[0].verificationURL);
    assert.ok(issuedToken, "expected verification token in email link");

    const resent = await requestJSON(PORT, "POST", "/v1/auth/resend-verification", {
      email: "verify-me@example.com"
    });
    assert.equal(resent.status, 200);

    const resentOutbox = await readOutbox(outboxFile);
    assert.equal(resentOutbox.length, 2, "expected resend verification email");
    const resentToken = extractToken(resentOutbox[1].verificationURL);
    assert.ok(resentToken, "expected token in resent verification link");
    assert.notEqual(resentToken, issuedToken, "expected resend to issue a fresh token");

    const verified = await requestJSON(PORT, "POST", "/v1/auth/verify-email", {
      token: issuedToken
    });
    assert.equal(verified.status, 200);

    let state = JSON.parse(await fs.readFile(dataFile, "utf8"));
    let identity = Object.values(state.authIdentities).find((item) => item.email === "verify-me@example.com");
    assert.ok(identity, "expected persisted email identity");
    assert.equal(identity.emailVerified, true);

    const reused = await requestJSON(PORT, "POST", "/v1/auth/verify-email", {
      token: issuedToken
    });
    assert.equal(reused.status, 400);

    const expiredCreated = await requestJSON(PORT, "POST", "/v1/auth/register", {
      email: "expired@example.com",
      password: "Password1!"
    });
    assert.equal(expiredCreated.status, 200);

    const secondOutbox = await readOutbox(outboxFile);
    assert.equal(secondOutbox.length, 3);
    const expiredToken = extractToken(secondOutbox[2].verificationURL);
    const expiredTokenHash = hashSHA256(expiredToken);

    await stopServer(child);
    child = null;

    state = JSON.parse(await fs.readFile(dataFile, "utf8"));
    const tokenRecord = Object.values(state.emailVerificationTokens).find((item) => item.tokenHash === expiredTokenHash);
    assert.ok(tokenRecord, "expected verification token record");
    tokenRecord.expiresAt = 1;
    await fs.writeFile(dataFile, JSON.stringify(state, null, 2), "utf8");

    child = startServer({ port: PORT, dataFile, mediaDir, outboxFile });
    await waitForHealth(PORT);

    const expired = await requestJSON(PORT, "POST", "/v1/auth/verify-email", {
      token: expiredToken
    });
    assert.equal(expired.status, 400);

    console.log("auth verify email contract: PASS");
  } finally {
    await stopServer(child);
    await fs.rm(tmp, { recursive: true, force: true });
  }
}

run().catch((error) => {
  console.error("auth verify email contract: FAIL");
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
