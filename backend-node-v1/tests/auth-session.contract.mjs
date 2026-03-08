import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import path from "node:path";
import os from "node:os";
import fs from "node:fs/promises";

const SERVER_DIR = process.cwd();
const PORT = 18232;

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

async function requestJSON(port, method, pathName, token, body) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const resp = await fetch(`http://127.0.0.1:${port}${pathName}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined
  });
  const data = await resp.json().catch(() => ({}));
  return { status: resp.status, data };
}

async function readOutbox(outboxFile) {
  try {
    return JSON.parse(await fs.readFile(outboxFile, "utf8"));
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
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "auth-session-"));
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

  const child = startServer({ port: PORT, dataFile, mediaDir, outboxFile });

  try {
    await waitForHealth(PORT);

    const registered = await requestJSON(PORT, "POST", "/v1/auth/register", null, {
      email: "session-user@example.com",
      password: "Password1!"
    });
    assert.equal(registered.status, 200);

    const blocked = await requestJSON(PORT, "POST", "/v1/auth/login", null, {
      email: "session-user@example.com",
      password: "Password1!"
    });
    assert.equal(blocked.status, 403);

    const outbox = await readOutbox(outboxFile);
    const verificationToken = extractToken(outbox[0].verificationURL);
    assert.ok(verificationToken);

    const verified = await requestJSON(PORT, "POST", "/v1/auth/verify-email", null, {
      token: verificationToken
    });
    assert.equal(verified.status, 200);

    const login = await requestJSON(PORT, "POST", "/v1/auth/login", null, {
      email: "session-user@example.com",
      password: "Password1!"
    });
    assert.equal(login.status, 200);
    assert.equal(typeof login.data.accessToken, "string");
    assert.equal(typeof login.data.refreshToken, "string");

    const me = await requestJSON(PORT, "GET", "/v1/profile/me", login.data.accessToken);
    assert.equal(me.status, 200);
    assert.equal(me.data.email, "session-user@example.com");

    const refreshed = await requestJSON(PORT, "POST", "/v1/auth/refresh", null, {
      refreshToken: login.data.refreshToken
    });
    assert.equal(refreshed.status, 200);
    assert.equal(typeof refreshed.data.accessToken, "string");

    const loggedOut = await requestJSON(PORT, "POST", "/v1/auth/logout", null, {
      refreshToken: login.data.refreshToken
    });
    assert.equal(loggedOut.status, 200);

    const refreshAfterLogout = await requestJSON(PORT, "POST", "/v1/auth/refresh", null, {
      refreshToken: login.data.refreshToken
    });
    assert.equal(refreshAfterLogout.status, 401);

    console.log("auth session contract: PASS");
  } finally {
    await stopServer(child);
    await fs.rm(tmp, { recursive: true, force: true });
  }
}

run().catch((error) => {
  console.error("auth session contract: FAIL");
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
