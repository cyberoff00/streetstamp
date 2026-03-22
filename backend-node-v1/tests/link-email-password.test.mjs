import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { spawn } from "node:child_process";

const SERVER_DIR = process.cwd();
let nextPort = 18480;

function emptyState() {
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

  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "link-email-pw-"));
  const dataFile = path.join(tmp, "data.json");
  const mediaDir = path.join(tmp, "media");
  const emailOutbox = path.join(tmp, "email-outbox.json");
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
      TEST_EMAIL_OUTBOX_FILE: emailOutbox,
      TEST_APPLE_OAUTH_FIXTURES: JSON.stringify({
        "apple-token-link-1": {
          sub: "apple_sub_link_1",
          email: "apple-user@example.com",
          email_verified: true
        }
      }),
      ...env
    },
    stdio: ["ignore", "pipe", "pipe"]
  });

  let logs = "";
  child.stdout?.on("data", (chunk) => { logs += String(chunk); });
  child.stderr?.on("data", (chunk) => { logs += String(chunk); });

  t.after(async () => {
    await stopServer(child);
    await fs.rm(tmp, { recursive: true, force: true });
  });

  await waitForHealth(port, () => logs);
  return { port, dataFile, emailOutbox };
}

async function postJSON(port, pathName, body, token) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers["Authorization"] = `Bearer ${token}`;
  const resp = await fetch(`http://127.0.0.1:${port}${pathName}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body)
  });
  const data = await resp.json().catch(() => ({}));
  return { status: resp.status, data };
}

async function getJSON(port, pathName, token) {
  const headers = token ? { Authorization: `Bearer ${token}` } : {};
  const resp = await fetch(`http://127.0.0.1:${port}${pathName}`, { headers });
  const data = await resp.json().catch(() => ({}));
  return { status: resp.status, data };
}

test("apple user can link email+password, then login with email after verification", async (t) => {
  const { port, dataFile, emailOutbox } = await startServer(t);

  // 1. Login with Apple
  const appleLogin = await postJSON(port, "/v1/auth/apple", { idToken: "apple-token-link-1" });
  assert.equal(appleLogin.status, 200);
  assert.ok(appleLogin.data.accessToken);
  assert.equal(appleLogin.data.hasEmailPassword, false);
  const appleToken = appleLogin.data.accessToken;

  // 2. Link email+password
  const linkResult = await postJSON(port, "/v1/auth/link-email-password", {
    email: "myemail@example.com",
    password: "Test1234!"
  }, appleToken);
  assert.equal(linkResult.status, 200);
  assert.equal(linkResult.data.ok, true);
  assert.equal(linkResult.data.emailVerificationRequired, true);

  // 3. Email login should fail before verification (email not verified)
  const loginBeforeVerify = await postJSON(port, "/v1/auth/login", {
    email: "myemail@example.com",
    password: "Test1234!"
  });
  assert.equal(loginBeforeVerify.status, 403);

  // 4. Read verification token from email outbox and verify it
  const outboxRaw = await fs.readFile(emailOutbox, "utf8");
  const outboxItems = JSON.parse(outboxRaw);
  const verifyEntry = outboxItems.find((e) => e.kind === "verify_email" && e.to === "myemail@example.com");
  assert.ok(verifyEntry, "verification email should have been sent");
  const tokenMatch = verifyEntry.verificationURL.match(/token=([^&]+)/);
  assert.ok(tokenMatch, "verification URL should contain token");
  const verificationToken = decodeURIComponent(tokenMatch[1]);

  const verifyResult = await postJSON(port, "/v1/auth/verify-email", { token: verificationToken });
  assert.equal(verifyResult.status, 200);
  assert.equal(verifyResult.data.ok, true);

  // 5. Now email login should succeed and return the same userId
  const loginAfterVerify = await postJSON(port, "/v1/auth/login", {
    email: "myemail@example.com",
    password: "Test1234!"
  });
  assert.equal(loginAfterVerify.status, 200);
  assert.equal(loginAfterVerify.data.userId, appleLogin.data.userId);
  assert.equal(loginAfterVerify.data.hasEmailPassword, true);
});

test("link-email-password requires authentication", async (t) => {
  const { port } = await startServer(t);

  const result = await postJSON(port, "/v1/auth/link-email-password", {
    email: "test@example.com",
    password: "Test1234!"
  });
  assert.equal(result.status, 401);
});

test("link-email-password rejects weak password", async (t) => {
  const { port } = await startServer(t);

  const appleLogin = await postJSON(port, "/v1/auth/apple", { idToken: "apple-token-link-1" });
  assert.equal(appleLogin.status, 200);

  const result = await postJSON(port, "/v1/auth/link-email-password", {
    email: "test@example.com",
    password: "short"
  }, appleLogin.data.accessToken);
  assert.equal(result.status, 400);
});

test("link-email-password rejects email already used by another account", async (t) => {
  const { port } = await startServer(t);

  // Register an email account first
  const reg = await postJSON(port, "/v1/auth/register", {
    email: "taken@example.com",
    password: "Test1234!",
    displayName: "Owner"
  });
  assert.equal(reg.status, 200);

  // Apple user tries to link same email
  const appleLogin = await postJSON(port, "/v1/auth/apple", { idToken: "apple-token-link-1" });
  assert.equal(appleLogin.status, 200);

  const result = await postJSON(port, "/v1/auth/link-email-password", {
    email: "taken@example.com",
    password: "Test1234!"
  }, appleLogin.data.accessToken);
  assert.equal(result.status, 409);
});

test("profile/me returns hasEmailPassword field", async (t) => {
  const { port } = await startServer(t);

  const appleLogin = await postJSON(port, "/v1/auth/apple", { idToken: "apple-token-link-1" });
  assert.equal(appleLogin.status, 200);

  // Before linking — should be false
  const profileBefore = await getJSON(port, "/v1/profile/me", appleLogin.data.accessToken);
  assert.equal(profileBefore.status, 200);
  assert.equal(profileBefore.data.hasEmailPassword, false);
});
