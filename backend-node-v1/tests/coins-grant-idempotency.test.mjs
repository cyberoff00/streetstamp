/**
 * /v1/coins/grant idempotency: replaying the same dedupe_token must not
 * double-credit. Requires Postgres (coins are relational-only), so the
 * test skips itself when DATABASE_URL is not set — run it on a box with
 * a database (CI or the server) to exercise the real path.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdtemp, rm, writeFile, readFile, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SERVER_PATH = join(import.meta.dirname, "..", "server.js");
const HAS_DB = Boolean((process.env.DATABASE_URL || "").trim());

function randEmail() {
  return `test_${randomBytes(6).toString("hex")}@example.com`;
}

function randPassword() {
  return `Test${randomBytes(4).toString("hex")}!1`;
}

async function withServer(fn) {
  const port = 19800 + Math.floor(Math.random() * 200);
  const tmpDir = await mkdtemp(join(tmpdir(), "ss-coins-"));
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
      WRITE_FREEZE_ENABLED: "false",
    },
    stdio: ["pipe", "pipe", "pipe"],
  });

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
    await fn({ api, apiAuth, registerAndLogin });
  } finally {
    proc.kill("SIGTERM");
    await new Promise((resolve) => {
      proc.on("close", resolve);
      setTimeout(() => { proc.kill("SIGKILL"); resolve(); }, 3000);
    });
    await rm(tmpDir, { recursive: true, force: true });
  }
}

test("grant with dedupe_token credits once, replay is a no-op", { skip: !HAS_DB && "requires DATABASE_URL" }, async () => {
  await withServer(async ({ apiAuth, registerAndLogin }) => {
    const session = await registerAndLogin(randEmail(), randPassword());
    const token = session.accessToken;
    const dedupeToken = `test_grant_${randomBytes(8).toString("hex")}`;

    const first = await apiAuth("/v1/coins/grant", token, {
      method: "POST",
      body: JSON.stringify({ amount: 100, reason: "test:iap", dedupe_token: dedupeToken }),
    });
    assert.equal(first.status, 200);
    assert.equal(first.body.applied, true);
    const balanceAfterFirst = first.body.balance;

    const replay = await apiAuth("/v1/coins/grant", token, {
      method: "POST",
      body: JSON.stringify({ amount: 100, reason: "test:iap", dedupe_token: dedupeToken }),
    });
    assert.equal(replay.status, 200);
    assert.equal(replay.body.applied, false);
    assert.equal(replay.body.balance, balanceAfterFirst);
  });
});

test("grant without dedupe_token keeps legacy behavior", { skip: !HAS_DB && "requires DATABASE_URL" }, async () => {
  await withServer(async ({ apiAuth, registerAndLogin }) => {
    const session = await registerAndLogin(randEmail(), randPassword());
    const token = session.accessToken;

    const first = await apiAuth("/v1/coins/grant", token, {
      method: "POST",
      body: JSON.stringify({ amount: 10, reason: "test:legacy" }),
    });
    assert.equal(first.status, 200);
    assert.equal(first.body.applied, true);

    const second = await apiAuth("/v1/coins/grant", token, {
      method: "POST",
      body: JSON.stringify({ amount: 10, reason: "test:legacy" }),
    });
    assert.equal(second.status, 200);
    assert.equal(second.body.balance, first.body.balance + 10);
  });
});
