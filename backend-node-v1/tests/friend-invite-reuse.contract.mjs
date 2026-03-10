import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";

const SERVER_DIR = process.cwd();
const PORT = 18152;

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

function startServer({ dataFile, mediaDir }) {
  return spawn("node", ["server.js"], {
    cwd: SERVER_DIR,
    env: {
      ...process.env,
      PORT: String(PORT),
      DATA_FILE: dataFile,
      MEDIA_DIR: mediaDir,
      MEDIA_PUBLIC_BASE: `http://127.0.0.1:${PORT}`,
      DATABASE_URL: ""
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

async function requestJSON(method, pathName, token, body) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;

  const resp = await fetch(`http://127.0.0.1:${PORT}${pathName}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined
  });

  const data = await resp.json().catch(() => ({}));
  return { status: resp.status, data };
}

async function registerUser(email) {
  const resp = await requestJSON("POST", "/v1/auth/email/register", null, {
    email,
    password: "password123"
  });
  assert.equal(resp.status, 200);
  return resp.data;
}

async function run() {
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "friend-invite-reuse-"));
  const dataFile = path.join(tmp, "data.json");
  const mediaDir = path.join(tmp, "media");
  await fs.writeFile(dataFile, JSON.stringify({
    users: {},
    emailIndex: {},
    inviteIndex: {},
    oauthIndex: {},
    firebaseIdentityIndex: {},
    handleIndex: {},
    likesIndex: {},
    friendRequestsIndex: {},
    postcardsIndex: {}
  }, null, 2), "utf8");

  let child = startServer({ dataFile, mediaDir });

  try {
    await waitForHealth(PORT);

    const sender = await registerUser(`sender_${Date.now()}@test.dev`);
    const receiver = await registerUser(`receiver_${Date.now()}@test.dev`);

    const me = await requestJSON("GET", "/v1/profile/me", receiver.accessToken);
    assert.equal(me.status, 200);
    const inviteCode = me.data.inviteCode;
    assert.ok(inviteCode);

    const initialRequest = await requestJSON("POST", "/v1/friends/requests", sender.accessToken, {
      inviteCode,
      displayName: "receiver"
    });
    assert.equal(initialRequest.status, 200);

    const incoming = await requestJSON("GET", "/v1/friends/requests", receiver.accessToken);
    assert.equal(incoming.status, 200);
    const requestID = incoming.data.incoming?.[0]?.id;
    assert.ok(requestID);

    const accept = await requestJSON("POST", `/v1/friends/requests/${requestID}/accept`, receiver.accessToken);
    assert.equal(accept.status, 200);

    const remove = await requestJSON("DELETE", `/v1/friends/${sender.userId}`, receiver.accessToken);
    assert.equal(remove.status, 200);

    await stopServer(child);
    child = null;

    const persisted = JSON.parse(await fs.readFile(dataFile, "utf8"));
    persisted.inviteIndex = {};
    await fs.writeFile(dataFile, JSON.stringify(persisted, null, 2), "utf8");

    child = startServer({ dataFile, mediaDir });
    await waitForHealth(PORT);

    const resend = await requestJSON("POST", "/v1/friends/requests", sender.accessToken, {
      inviteCode,
      displayName: "receiver"
    });
    assert.equal(resend.status, 200);
    assert.equal(resend.data.ok, true);

    console.log("friend invite reuse contract: PASS");
  } finally {
    await stopServer(child);
    await fs.rm(tmp, { recursive: true, force: true });
  }
}

run().catch((err) => {
  console.error("friend invite reuse contract: FAIL");
  console.error(err && err.stack ? err.stack : err);
  process.exit(1);
});
