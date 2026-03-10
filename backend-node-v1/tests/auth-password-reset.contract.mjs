import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import path from "node:path";
import os from "node:os";
import fs from "node:fs/promises";

const SERVER_DIR = process.cwd();
const PORT = 18233;

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

async function requestText(port, pathName) {
  const resp = await fetch(`http://127.0.0.1:${port}${pathName}`);
  const text = await resp.text();
  return {
    status: resp.status,
    contentType: resp.headers.get("content-type") || "",
    text
  };
}

async function readOutbox(outboxFile) {
  try {
    return JSON.parse(await fs.readFile(outboxFile, "utf8"));
  } catch (error) {
    if (error && error.code === "ENOENT") return [];
    throw error;
  }
}

function extractToken(resetURL) {
  const url = new URL(resetURL);
  return url.searchParams.get("token");
}

async function run() {
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "auth-password-reset-"));
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
      email: "reset-me@example.com",
      password: "Password1!"
    });
    assert.equal(registered.status, 200);

    const registerOutbox = await readOutbox(outboxFile);
    const verifyToken = new URL(registerOutbox[0].verificationURL).searchParams.get("token");
    const verified = await requestJSON(PORT, "POST", "/v1/auth/verify-email", null, { token: verifyToken });
    assert.equal(verified.status, 200);

    const login = await requestJSON(PORT, "POST", "/v1/auth/login", null, {
      email: "reset-me@example.com",
      password: "Password1!"
    });
    assert.equal(login.status, 200);

    const missing = await requestJSON(PORT, "POST", "/v1/auth/forgot-password", null, {
      email: "not-found@example.com"
    });
    assert.equal(missing.status, 200);

    const forgot = await requestJSON(PORT, "POST", "/v1/auth/forgot-password", null, {
      email: "reset-me@example.com"
    });
    assert.equal(forgot.status, 200);

    const forgotOutbox = await readOutbox(outboxFile);
    const resetMail = forgotOutbox.find((item) => item.kind === "password_reset" && item.to === "reset-me@example.com");
    assert.ok(resetMail, "expected password reset email");
    assert.equal(
      resetMail.resetURL.startsWith(`http://127.0.0.1:${PORT}/reset-password?token=`),
      true,
      "expected password reset link to use the browser landing route"
    );
    const resetToken = extractToken(resetMail.resetURL);
    assert.ok(resetToken);

    const resetPage = await requestText(PORT, `/reset-password?token=${encodeURIComponent(resetToken)}`);
    assert.equal(resetPage.status, 200);
    assert.match(resetPage.contentType, /text\/html/i);
    assert.match(resetPage.text, /streetstamps:\/\/reset-password\?token=/i);

    const invalidResetPage = await requestText(PORT, "/reset-password?token=invalid-token");
    assert.equal(invalidResetPage.status, 400);
    assert.match(invalidResetPage.text, /invalid|expired|reset/i);

    const reset = await requestJSON(PORT, "POST", "/v1/auth/reset-password", null, {
      token: resetToken,
      newPassword: "Changed1!"
    });
    assert.equal(reset.status, 200);

    const reused = await requestJSON(PORT, "POST", "/v1/auth/reset-password", null, {
      token: resetToken,
      newPassword: "Changed2!"
    });
    assert.equal(reused.status, 400);

    const refreshAfterReset = await requestJSON(PORT, "POST", "/v1/auth/refresh", null, {
      refreshToken: login.data.refreshToken
    });
    assert.equal(refreshAfterReset.status, 401);

    const oldPasswordLogin = await requestJSON(PORT, "POST", "/v1/auth/login", null, {
      email: "reset-me@example.com",
      password: "Password1!"
    });
    assert.equal(oldPasswordLogin.status, 401);

    const newPasswordLogin = await requestJSON(PORT, "POST", "/v1/auth/login", null, {
      email: "reset-me@example.com",
      password: "Changed1!"
    });
    assert.equal(newPasswordLogin.status, 200);

    console.log("auth password reset contract: PASS");
  } finally {
    await stopServer(child);
    await fs.rm(tmp, { recursive: true, force: true });
  }
}

run().catch((error) => {
  console.error("auth password reset contract: FAIL");
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
