import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { spawn } from "node:child_process";

const SERVER_DIR = process.cwd();
let nextPort = 18210;

function makeLegacyState() {
  return {
    users: {},
    emailIndex: {},
    inviteIndex: {},
    oauthIndex: {},
    firebaseIdentityIndex: {},
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
  const detail = logs && logs.trim() ? `\n${logs}` : "";
  throw new Error(`server did not become healthy${detail}`);
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

async function startServer(t, initialState) {
  const port = nextPort;
  nextPort += 1;

  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "self-hosted-auth-schema-"));
  const dataFile = path.join(tmp, "data.json");
  const mediaDir = path.join(tmp, "media");
  await fs.writeFile(dataFile, JSON.stringify(initialState, null, 2), "utf8");
  await fs.mkdir(mediaDir, { recursive: true });

  const child = spawn("node", ["server.js"], {
    cwd: SERVER_DIR,
    env: {
      ...process.env,
      PORT: String(port),
      DATA_FILE: dataFile,
      MEDIA_DIR: mediaDir,
      MEDIA_PUBLIC_BASE: `http://127.0.0.1:${port}`,
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

  t.after(async () => {
    await stopServer(child);
    await fs.rm(tmp, { recursive: true, force: true });
  });

  await waitForHealth(port, () => logs);

  return {
    port,
    readState: async () => JSON.parse(await fs.readFile(dataFile, "utf8"))
  };
}

test("email registration persists the new self-hosted auth structures", async (t) => {
  const { port, readState } = await startServer(t, makeLegacyState());

  const resp = await requestJSON(port, "POST", "/v1/auth/email/register", {
    email: `schema_${Date.now()}@example.com`,
    password: "Password1!"
  });

  assert.equal(resp.status, 200);

  const state = await readState();

  assert.ok(state.authIdentities, "expected authIdentities collection");
  assert.ok(state.emailVerificationTokens, "expected emailVerificationTokens collection");
  assert.ok(state.passwordResetTokens, "expected passwordResetTokens collection");
  assert.ok(state.refreshTokens, "expected refreshTokens collection");

  const identities = Object.values(state.authIdentities);
  assert.equal(identities.length, 1, "expected one persisted auth identity");
});
