import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { spawn } from "node:child_process";

const SERVER_DIR = process.cwd();
let nextPort = 18380;

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

  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "write-freeze-"));
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

test("health exposes write freeze mode when migration freeze is enabled", async (t) => {
  const { port } = await startServer(t, {
    WRITE_FREEZE_ENABLED: "true"
  });

  const resp = await fetch(`http://127.0.0.1:${port}/v1/health`);
  const data = await resp.json();

  assert.equal(resp.status, 200);
  assert.equal(data.maintenance.writeFrozen, true);
});

test("write endpoints reject requests when migration freeze is enabled", async (t) => {
  const { port } = await startServer(t, {
    WRITE_FREEZE_ENABLED: "true"
  });

  const resp = await fetch(`http://127.0.0.1:${port}/v1/profile/setup`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      displayName: "Frozen User",
      loadout: {}
    })
  });
  const data = await resp.json();

  assert.equal(resp.status, 503);
  assert.equal(data.code, "write_frozen");
});
