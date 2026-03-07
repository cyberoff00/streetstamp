import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";

const SERVER_DIR = process.cwd();
let nextPort = 18125;

function makeUser(id, overrides = {}) {
  return {
    id,
    provider: "email",
    email: null,
    passwordHash: null,
    inviteCode: `INV${id.slice(-5).toUpperCase()}`,
    handle: id.slice(0, 24),
    handleChangeUsed: false,
    profileVisibility: "friendsOnly",
    displayName: "Explorer",
    bio: "Travel Enthusiastic",
    loadout: {
      species: "boy",
      color: "yellow",
      accessory: null,
      headgear: null,
      handheld: null
    },
    journeys: [],
    cityCards: [],
    friendIDs: [],
    notifications: [],
    sentPostcards: [],
    receivedPostcards: [],
    createdAt: 1771000000,
    ...overrides
  };
}

function makeDB(overrides = {}) {
  return {
    users: {},
    emailIndex: {},
    inviteIndex: {},
    oauthIndex: {},
    handleIndex: {},
    likesIndex: {},
    friendRequestsIndex: {},
    postcardsIndex: {},
    ...overrides
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

async function requestJSON(port, method, pathName, token) {
  const headers = {};
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }
  const resp = await fetch(`http://127.0.0.1:${port}${pathName}`, { method, headers });
  const data = await resp.json().catch(() => ({}));
  return { status: resp.status, data };
}

async function startServer(db, fixtures, options = {}) {
  const port = nextPort;
  nextPort += 1;

  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "firebase-auth-"));
  const dataFile = path.join(tmp, "data.json");
  const mediaDir = path.join(tmp, "media");
  await fs.writeFile(dataFile, JSON.stringify(db, null, 2), "utf8");
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
      FIREBASE_AUTH_ENABLED: "1",
      FIREBASE_PROJECT_ID: "streetstamps-firebase-tests",
      FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({ project_id: "streetstamps-firebase-tests" }),
      FIREBASE_LEGACY_EMAIL: "yinterestingy@gmail.com",
      FIREBASE_LEGACY_APP_USER_ID: options.legacyAppUserId || "u_legacy_preserved",
      TEST_FIREBASE_AUTH_FIXTURES: JSON.stringify(fixtures || {})
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

  await waitForHealth(port, () => logs);
  return {
    port,
    readDB: async () => JSON.parse(await fs.readFile(dataFile, "utf8")),
    cleanup: async () => {
      await stopServer(child);
      await fs.rm(tmp, { recursive: true, force: true });
    }
  };
}

async function testCreatesIdentityMapping() {
  const token = "firebase-create-user-token";
  const firebaseUID = "firebase-user-001";
  const email = "firebase-new-user@example.com";
  const fixtures = {
    [token]: {
      uid: firebaseUID,
      email,
      email_verified: true,
      firebase: { sign_in_provider: "password" }
    }
  };
  const server = await startServer(makeDB(), fixtures);
  try {
    const resp = await requestJSON(server.port, "GET", "/v1/profile/me", token);

    assert.equal(resp.status, 200);
    assert.equal(resp.data.email, email);

    const saved = await server.readDB();
    assert.ok(saved.firebaseIdentityIndex);
    assert.equal(saved.firebaseIdentityIndex[firebaseUID].email, email);
    assert.equal(saved.firebaseIdentityIndex[firebaseUID].emailVerified, true);
    assert.deepEqual(saved.firebaseIdentityIndex[firebaseUID].providers, ["password"]);
    assert.equal(saved.users[resp.data.id].email, email);
  } finally {
    await server.cleanup();
  }
}

async function testReusesIdentityMapping() {
  const firstToken = "firebase-repeat-token-1";
  const secondToken = "firebase-repeat-token-2";
  const firebaseUID = "firebase-repeat-user";
  const fixtures = {
    [firstToken]: {
      uid: firebaseUID,
      email: "repeat@example.com",
      email_verified: true,
      firebase: { sign_in_provider: "google.com" }
    },
    [secondToken]: {
      uid: firebaseUID,
      email: "repeat@example.com",
      email_verified: true,
      firebase: { sign_in_provider: "google.com" }
    }
  };
  const server = await startServer(makeDB(), fixtures);
  try {
    const first = await requestJSON(server.port, "GET", "/v1/profile/me", firstToken);
    const second = await requestJSON(server.port, "GET", "/v1/profile/me", secondToken);

    assert.equal(first.status, 200);
    assert.equal(second.status, 200);
    assert.equal(first.data.id, second.data.id);

    const saved = await server.readDB();
    assert.equal(Object.keys(saved.users).length, 1);
    assert.equal(saved.firebaseIdentityIndex[firebaseUID].appUserId, first.data.id);
  } finally {
    await server.cleanup();
  }
}

async function testBindsLegacyAccount() {
  const token = "firebase-legacy-token";
  const firebaseUID = "firebase-legacy-user";
  const legacyAppUserId = "u_legacy_preserved";
  const db = makeDB({
    users: {
      [legacyAppUserId]: makeUser(legacyAppUserId, {
        provider: "email",
        email: "yinterestingy@gmail.com",
        handle: "legacy_preserved"
      })
    },
    emailIndex: {
      "yinterestingy@gmail.com": legacyAppUserId
    }
  });
  const fixtures = {
    [token]: {
      uid: firebaseUID,
      email: "yinterestingy@gmail.com",
      email_verified: true,
      firebase: { sign_in_provider: "password" }
    }
  };
  const server = await startServer(db, fixtures, { legacyAppUserId });
  try {
    const resp = await requestJSON(server.port, "GET", "/v1/profile/me", token);

    assert.equal(resp.status, 200);
    assert.equal(resp.data.id, legacyAppUserId);

    const saved = await server.readDB();
    assert.equal(saved.firebaseIdentityIndex[firebaseUID].appUserId, legacyAppUserId);
  } finally {
    await server.cleanup();
  }
}

async function testRejectsUnauthenticatedRequest() {
  const server = await startServer(makeDB(), {});
  try {
    const resp = await requestJSON(server.port, "GET", "/v1/profile/me");
    assert.equal(resp.status, 401);
  } finally {
    await server.cleanup();
  }
}

async function run() {
  await testCreatesIdentityMapping();
  await testReusesIdentityMapping();
  await testBindsLegacyAccount();
  await testRejectsUnauthenticatedRequest();
  console.log("firebase auth contract: PASS");
}

run().catch((error) => {
  console.error("firebase auth contract: FAIL");
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
