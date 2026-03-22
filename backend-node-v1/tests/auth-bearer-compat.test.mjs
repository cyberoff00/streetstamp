import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { spawn } from "node:child_process";

const SERVER_DIR = process.cwd();
let nextPort = 18360;

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

  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "auth-bearer-compat-"));
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

async function requestJSON(port, pathName, token) {
  const headers = token ? { Authorization: `Bearer ${token}` } : {};
  const resp = await fetch(`http://127.0.0.1:${port}${pathName}`, { headers });
  const data = await resp.json().catch(() => ({}));
  return { status: resp.status, data };
}

test("health exposes backend-only auth mode when firebase bearer compatibility is disabled", async (t) => {
  const { port } = await startServer(t, {
    FIREBASE_BEARER_COMPAT_ENABLED: "false"
  });

  const resp = await fetch(`http://127.0.0.1:${port}/v1/health`);
  const data = await resp.json();

  assert.equal(resp.status, 200);
  assert.equal(data.auth.businessBearer, "backend_jwt_only");
  assert.equal(data.auth.firebaseBearerCompat, false);
});

test("firebase bearer token is rejected for business APIs when compatibility is disabled", async (t) => {
  const { port } = await startServer(t, {
    FIREBASE_BEARER_COMPAT_ENABLED: "false",
    TEST_FIREBASE_AUTH_FIXTURES: JSON.stringify({
      "firebase-token-1": {
        uid: "firebase_uid_1",
        email: "firebase@example.com",
        email_verified: true,
        firebase: {
          sign_in_provider: "password"
        }
      }
    })
  });

  const result = await requestJSON(port, "/v1/profile/me", "firebase-token-1");
  assert.equal(result.status, 401);
  assert.equal(result.data.message, "unauthorized");
});

test("firebase bearer token can still authenticate business APIs when compatibility is enabled", async (t) => {
  const { port } = await startServer(t, {
    FIREBASE_BEARER_COMPAT_ENABLED: "true",
    TEST_FIREBASE_AUTH_FIXTURES: JSON.stringify({
      "firebase-token-2": {
        uid: "firebase_uid_2",
        email: "firebase2@example.com",
        email_verified: true,
        firebase: {
          sign_in_provider: "password"
        }
      }
    })
  });

  const result = await requestJSON(port, "/v1/profile/me", "firebase-token-2");
  assert.equal(result.status, 200);
  assert.equal(result.data.email, "firebase2@example.com");
});
