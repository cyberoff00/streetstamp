import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { spawn } from "node:child_process";

const SERVER_DIR = process.cwd();
const GOOGLE_STUB_PATH = path.join(SERVER_DIR, "tests/helpers/google-oauth-stub.cjs");
let nextPort = 18150;

function hashSHA256(raw) {
  return crypto.createHash("sha256").update(raw).digest("hex");
}

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

function makeJourney(id) {
  return {
    id,
    title: `Journey ${id}`,
    distance: 1200,
    startTime: "2026-03-01T10:00:00.000Z",
    endTime: "2026-03-01T11:00:00.000Z",
    visibility: "friendsOnly",
    routeCoordinates: [
      { lat: 48.8566, lon: 2.3522 },
      { lat: 48.857, lon: 2.353 }
    ],
    memories: []
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
    await new Promise((r) => setTimeout(r, 120));
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

async function startServer(t, db, fixtures) {
  const port = nextPort;
  nextPort += 1;

  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "oauth-unify-"));
  const dataFile = path.join(tmp, "data.json");
  const mediaDir = path.join(tmp, "media");
  await fs.writeFile(dataFile, JSON.stringify(db, null, 2), "utf8");
  await fs.mkdir(mediaDir, { recursive: true });

  const existingNodeOptions = process.env.NODE_OPTIONS ? `${process.env.NODE_OPTIONS} ` : "";
  const child = spawn("node", ["server.js"], {
    cwd: SERVER_DIR,
    env: {
      ...process.env,
      PORT: String(port),
      DATA_FILE: dataFile,
      MEDIA_DIR: mediaDir,
      MEDIA_PUBLIC_BASE: `http://127.0.0.1:${port}`,
      DATABASE_URL: "",
      NODE_OPTIONS: `${existingNodeOptions}--require ${GOOGLE_STUB_PATH}`.trim(),
      TEST_GOOGLE_OAUTH_FIXTURES: JSON.stringify(fixtures)
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
    readDB: async () => JSON.parse(await fs.readFile(dataFile, "utf8"))
  };
}

test("oauth login reuses legacy hashed mapping and writes the modern key", async (t) => {
  const idToken = "legacy-token";
  const subject = "google-subject-legacy";
  const legacyKey = `google:${hashSHA256(idToken)}`;
  const modernKey = `google:${subject}`;
  const legacyUID = "u_legacy000000000000000001";

  const db = makeDB({
    users: {
      [legacyUID]: makeUser(legacyUID, {
        provider: "google",
        handle: "legacy_google_user",
        journeys: [makeJourney("j_legacy")]
      })
    },
    oauthIndex: { [legacyKey]: legacyUID }
  });

  const { port, readDB } = await startServer(t, db, {
    [idToken]: { sub: subject, email_verified: false }
  });

  const resp = await requestJSON(port, "POST", "/v1/auth/oauth", {
    provider: "google",
    idToken
  });

  assert.equal(resp.status, 200);
  assert.equal(resp.data.userId, legacyUID);

  const saved = await readDB();
  assert.equal(saved.oauthIndex[modernKey], legacyUID);
  assert.equal(saved.oauthIndex[legacyKey], legacyUID);
  assert.equal(Object.keys(saved.users).length, 1);
});

test("oauth login merges a mistaken empty modern account into the legacy account", async (t) => {
  const idToken = "merge-empty-token";
  const subject = "google-subject-empty-merge";
  const legacyKey = `google:${hashSHA256(idToken)}`;
  const modernKey = `google:${subject}`;
  const legacyUID = "u_legacy000000000000000002";
  const emptyUID = "u_empty0000000000000000003";

  const db = makeDB({
    users: {
      [legacyUID]: makeUser(legacyUID, {
        provider: "google",
        handle: "legacy_merge_target",
        journeys: [makeJourney("j_kept")]
      }),
      [emptyUID]: makeUser(emptyUID, {
        provider: "google",
        handle: "mistaken_empty_modern",
        createdAt: 1772401488
      })
    },
    oauthIndex: {
      [legacyKey]: legacyUID,
      [modernKey]: emptyUID
    }
  });

  const { port, readDB } = await startServer(t, db, {
    [idToken]: { sub: subject, email_verified: false }
  });

  const resp = await requestJSON(port, "POST", "/v1/auth/oauth", {
    provider: "google",
    idToken
  });

  assert.equal(resp.status, 200);
  assert.equal(resp.data.userId, legacyUID);

  const saved = await readDB();
  assert.equal(saved.oauthIndex[modernKey], legacyUID);
  assert.equal(saved.oauthIndex[legacyKey], legacyUID);
  assert.equal(saved.users[legacyUID].journeys.length, 1);
  assert.equal(saved.users[emptyUID], undefined);
});

test("oauth login reuses the verified email account instead of creating a second account", async (t) => {
  const idToken = "email-merge-token";
  const subject = "google-subject-email-merge";
  const modernKey = `google:${subject}`;
  const email = "existing@example.com";
  const emailUID = "u_email0000000000000000004";

  const db = makeDB({
    users: {
      [emailUID]: makeUser(emailUID, {
        provider: "email",
        email,
        handle: "email_owner",
        journeys: [makeJourney("j_email")]
      })
    },
    emailIndex: { [email]: emailUID }
  });

  const { port, readDB } = await startServer(t, db, {
    [idToken]: { sub: subject, email, email_verified: true }
  });

  const resp = await requestJSON(port, "POST", "/v1/auth/oauth", {
    provider: "google",
    idToken
  });

  assert.equal(resp.status, 200);
  assert.equal(resp.data.userId, emailUID);

  const saved = await readDB();
  assert.equal(saved.oauthIndex[modernKey], emailUID);
  assert.equal(Object.keys(saved.users).length, 1);
});

test("oauth login does not auto-merge when the modern account already has data", async (t) => {
  const idToken = "conflict-token";
  const subject = "google-subject-conflict";
  const legacyKey = `google:${hashSHA256(idToken)}`;
  const modernKey = `google:${subject}`;
  const legacyUID = "u_legacy000000000000000005";
  const modernUID = "u_modern000000000000000006";

  const db = makeDB({
    users: {
      [legacyUID]: makeUser(legacyUID, {
        provider: "google",
        handle: "legacy_conflict_user",
        journeys: [makeJourney("j_legacy_conflict")]
      }),
      [modernUID]: makeUser(modernUID, {
        provider: "google",
        handle: "modern_conflict_user",
        notifications: [{ id: "n1", type: "journey_like", read: false }]
      })
    },
    oauthIndex: {
      [legacyKey]: legacyUID,
      [modernKey]: modernUID
    }
  });

  const { port, readDB } = await startServer(t, db, {
    [idToken]: { sub: subject, email_verified: false }
  });

  const resp = await requestJSON(port, "POST", "/v1/auth/oauth", {
    provider: "google",
    idToken
  });

  assert.equal(resp.status, 200);
  assert.equal(resp.data.userId, modernUID);

  const saved = await readDB();
  assert.ok(saved.users[legacyUID]);
  assert.ok(saved.users[modernUID]);
  assert.equal(saved.oauthIndex[modernKey], modernUID);
  assert.equal(saved.oauthIndex[legacyKey], legacyUID);
});
