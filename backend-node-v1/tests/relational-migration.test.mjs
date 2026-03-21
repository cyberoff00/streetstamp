/**
 * Tests that the relational migration path works correctly.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdtemp, rm, writeFile, readFile, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SERVER_PATH = join(import.meta.dirname, "..", "server.js");

function randEmail() {
  return `test_${randomBytes(6).toString("hex")}@example.com`;
}

function randPassword() {
  return `Test${randomBytes(4).toString("hex")}!1`;
}

async function withServer(fn) {
  const port = 19800 + Math.floor(Math.random() * 200);
  const tmpDir = await mkdtemp(join(tmpdir(), "ss-rel-"));
  const dataDir = join(tmpDir, "data");
  const mediaDir = join(tmpDir, "media");
  await mkdir(dataDir, { recursive: true });
  await mkdir(mediaDir, { recursive: true });
  const emailOutbox = join(tmpDir, "email-outbox.json");
  await writeFile(emailOutbox, "[]", "utf8");

  const proc = spawn("node", [SERVER_PATH], {
    env: {
      ...process.env,
      PORT: String(port),
      JWT_SECRET: "test-secret-that-is-at-least-32-characters-long-ok",
      DATA_FILE: join(dataDir, "data.json"),
      MEDIA_DIR: mediaDir,
      TEST_EMAIL_OUTBOX_FILE: emailOutbox,
      CORS_ALLOWED_ORIGINS: "",
      FIREBASE_AUTH_ENABLED: "0",
      FIREBASE_BEARER_COMPAT_ENABLED: "false",
      WRITE_FREEZE_ENABLED: "false",
    },
    stdio: ["pipe", "pipe", "pipe"],
  });

  let serverStderr = "";
  proc.stderr.on("data", (d) => { serverStderr += d.toString(); });

  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("server startup timeout")), 10000);
    proc.stdout.on("data", (chunk) => {
      if (chunk.toString().includes("listening on")) {
        clearTimeout(timeout);
        resolve();
      }
    });
    proc.on("error", reject);
  });

  const base = `http://127.0.0.1:${port}`;

  async function api(path, options = {}) {
    const { headers: extraHeaders, ...rest } = options;
    const res = await fetch(`${base}${path}`, {
      ...rest,
      headers: { "Content-Type": "application/json", ...extraHeaders },
    });
    const body = await res.json().catch(() => null);
    return { status: res.status, body };
  }

  async function apiAuth(path, token, options = {}) {
    return api(path, {
      ...options,
      headers: { Authorization: `Bearer ${token}`, ...options.headers },
    });
  }

  async function registerAndLogin(email, password) {
    const reg = await api("/v1/auth/register", {
      method: "POST",
      body: JSON.stringify({ email, password }),
    });
    if (reg.status !== 200) throw new Error(`register failed: ${JSON.stringify(reg.body)}`);

    const outbox = JSON.parse(await readFile(emailOutbox, "utf8"));
    const entry = outbox.filter((e) => e.to === email).pop();
    if (!entry) throw new Error("no verification email found");
    const token = new URL(entry.verificationURL).searchParams.get("token");

    const verify = await api("/v1/auth/verify-email", {
      method: "POST",
      body: JSON.stringify({ token }),
    });
    if (verify.status !== 200) throw new Error(`verify failed: ${JSON.stringify(verify.body)}`);

    const login = await api("/v1/auth/login", {
      method: "POST",
      body: JSON.stringify({ email, password }),
    });
    if (login.status !== 200) throw new Error(`login failed: ${JSON.stringify(login.body)}`);

    return login.body;
  }

  try {
    await fn({ api, apiAuth, registerAndLogin, emailOutbox, serverStderr: () => serverStderr });
  } finally {
    proc.kill("SIGTERM");
    await new Promise((resolve) => {
      proc.on("close", resolve);
      setTimeout(() => { proc.kill("SIGKILL"); resolve(); }, 3000);
    });
    await rm(tmpDir, { recursive: true, force: true });
  }
}

test("health reports file storage without DATABASE_URL", async () => {
  await withServer(async ({ api }) => {
    const { status, body } = await api("/v1/health");
    assert.equal(status, 200);
    assert.equal(body.status, "ok");
    assert.equal(body.storage, "file");
  });
});

test("register + verify + login round-trip", async () => {
  await withServer(async ({ registerAndLogin }) => {
    const session = await registerAndLogin(randEmail(), randPassword());
    assert.ok(session.accessToken);
    assert.ok(session.refreshToken);
    assert.ok(session.userId);
  });
});

test("journey migrate persists and is returned in profile", async () => {
  await withServer(async ({ apiAuth, registerAndLogin }) => {
    const session = await registerAndLogin(randEmail(), randPassword());

    const migrate = await apiAuth("/v1/journeys/migrate", session.accessToken, {
      method: "POST",
      body: JSON.stringify({
        journeys: [{
          id: "j_test1",
          title: "Test Journey",
          distance: 1000,
          startTime: "2026-01-01T00:00:00Z",
          endTime: "2026-01-01T01:00:00Z",
          visibility: "public",
          routeCoordinates: [{ lat: 31.23, lon: 121.47 }],
          memories: [],
        }],
        unlockedCityCards: [{ id: "Shanghai|CN", name: "Shanghai", countryISO2: "CN" }],
        snapshotComplete: true,
      }),
    });
    assert.equal(migrate.status, 200, `migrate failed: ${JSON.stringify(migrate.body)}`);
    assert.equal(migrate.body.journeys, 1);

    const profile = await apiAuth("/v1/profile/me", session.accessToken);
    assert.equal(profile.status, 200);
    assert.equal(profile.body.stats.totalJourneys, 1,
      `expected 1 journey, got ${profile.body.stats.totalJourneys}`);
  });
});

test("friend request flow works", async () => {
  await withServer(async ({ api, apiAuth, registerAndLogin }) => {
    const user1 = await registerAndLogin(randEmail(), randPassword());
    const user2 = await registerAndLogin(randEmail(), randPassword());

    // Get user2's invite code
    const profile2 = await apiAuth("/v1/profile/me", user2.accessToken);
    const inviteCode = profile2.body.inviteCode;

    // User1 sends friend request
    const reqRes = await apiAuth("/v1/friends/requests", user1.accessToken, {
      method: "POST",
      body: JSON.stringify({ inviteCode }),
    });
    assert.equal(reqRes.status, 200, `friend request failed: ${JSON.stringify(reqRes.body)}`);
    assert.ok(reqRes.body.request.id);

    // User2 sees incoming request
    const incoming = await apiAuth("/v1/friends/requests", user2.accessToken);
    assert.equal(incoming.status, 200);
    assert.equal(incoming.body.incoming.length, 1);

    // User2 accepts
    const acceptRes = await apiAuth(
      `/v1/friends/requests/${incoming.body.incoming[0].id}/accept`,
      user2.accessToken,
      { method: "POST" }
    );
    assert.equal(acceptRes.status, 200);

    // Verify friendship
    const friends1 = await apiAuth("/v1/friends", user1.accessToken);
    assert.equal(friends1.body.length, 1);
    assert.equal(friends1.body[0].id, user2.userId);
  });
});
