import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";

const SERVER_DIR = process.cwd();
let nextPort = 18135;

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
    firebaseIdentityIndex: {},
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

async function startServer(db, fixtures, options = {}) {
  const port = nextPort;
  nextPort += 1;

  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "firebase-auth-profile-"));
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

async function testFirebaseBearerCanLoadProfileAndUsePostcardRoutes() {
  const senderID = "u_firebase_sender_001";
  const receiverID = "u_firebase_receiver_002";
  const senderToken = "firebase-sender-token";
  const receiverToken = "firebase-receiver-token";

  const db = makeDB({
    users: {
      [senderID]: makeUser(senderID, {
        provider: "google",
        email: "sender@example.com",
        displayName: "Sender",
        friendIDs: [receiverID]
      }),
      [receiverID]: makeUser(receiverID, {
        provider: "password",
        email: "receiver@example.com",
        displayName: "Receiver",
        friendIDs: [senderID]
      })
    },
    emailIndex: {
      "sender@example.com": senderID,
      "receiver@example.com": receiverID
    }
  });

  const fixtures = {
    [senderToken]: {
      uid: "firebase-sender-uid",
      email: "sender@example.com",
      email_verified: true,
      firebase: { sign_in_provider: "google.com" }
    },
    [receiverToken]: {
      uid: "firebase-receiver-uid",
      email: "receiver@example.com",
      email_verified: true,
      firebase: { sign_in_provider: "password" }
    }
  };

  const server = await startServer(db, fixtures);
  try {
    const me = await requestJSON(server.port, "GET", "/v1/profile/me", senderToken);
    assert.equal(me.status, 200);
    assert.equal(me.data.id, senderID);

    const send = await requestJSON(server.port, "POST", "/v1/postcards/send", senderToken, {
      clientDraftID: "firebase-draft-1",
      toUserID: receiverID,
      cityID: "paris",
      cityName: "Paris",
      messageText: "hello from firebase",
      photoURL: "/media/fake.jpg",
      allowedCityIDs: ["paris"]
    });
    assert.equal(send.status, 200);
    assert.ok(send.data.messageID);

    const sent = await requestJSON(server.port, "GET", "/v1/postcards?box=sent", senderToken);
    assert.equal(sent.status, 200);
    assert.equal(sent.data.items.length, 1);
    assert.equal(sent.data.items[0].messageID, send.data.messageID);

    const received = await requestJSON(server.port, "GET", "/v1/postcards?box=received", receiverToken);
    assert.equal(received.status, 200);
    assert.equal(received.data.items.length, 1);
    assert.equal(received.data.items[0].messageID, send.data.messageID);

    const notifications = await requestJSON(server.port, "GET", "/v1/notifications?unreadOnly=0", receiverToken);
    assert.equal(notifications.status, 200);
    const postcardNotice = (notifications.data.items || []).find((item) => item.type === "postcard_received");
    assert.ok(postcardNotice, "expected postcard_received notification");
    assert.equal(postcardNotice.messageText, "hello from firebase");

    const saved = await server.readDB();
    assert.equal(saved.firebaseIdentityIndex["firebase-sender-uid"].appUserId, senderID);
    assert.equal(saved.firebaseIdentityIndex["firebase-receiver-uid"].appUserId, receiverID);
  } finally {
    await server.cleanup();
  }
}

async function testPreservedLegacyEmailReusesHistoricalAccountAcrossRepeatedSignIns() {
  const legacyAppUserId = "u_legacy_preserved";
  const firstToken = "firebase-legacy-first";
  const secondToken = "firebase-legacy-second";

  const db = makeDB({
    users: {
      [legacyAppUserId]: makeUser(legacyAppUserId, {
        provider: "email",
        email: "yinterestingy@gmail.com",
        displayName: "Historical Business Owner",
        handle: "legacy_business_owner"
      })
    },
    emailIndex: {
      "yinterestingy@gmail.com": legacyAppUserId
    }
  });

  const fixtures = {
    [firstToken]: {
      uid: "firebase-legacy-uid-1",
      email: "yinterestingy@gmail.com",
      email_verified: true,
      firebase: { sign_in_provider: "password" }
    },
    [secondToken]: {
      uid: "firebase-legacy-uid-2",
      email: "yinterestingy@gmail.com",
      email_verified: true,
      firebase: { sign_in_provider: "google.com" }
    }
  };

  const server = await startServer(db, fixtures, { legacyAppUserId });
  try {
    const first = await requestJSON(server.port, "GET", "/v1/profile/me", firstToken);
    const second = await requestJSON(server.port, "GET", "/v1/profile/me", secondToken);

    assert.equal(first.status, 200);
    assert.equal(second.status, 200);
    assert.equal(first.data.id, legacyAppUserId);
    assert.equal(second.data.id, legacyAppUserId);
    assert.equal(first.data.handle, "legacy_business_owner");
    assert.equal(second.data.handle, "legacy_business_owner");

    const saved = await server.readDB();
    assert.equal(saved.firebaseIdentityIndex["firebase-legacy-uid-1"].appUserId, legacyAppUserId);
    assert.equal(saved.firebaseIdentityIndex["firebase-legacy-uid-2"].appUserId, legacyAppUserId);
    assert.equal(Object.keys(saved.users).length, 1);
  } finally {
    await server.cleanup();
  }
}

async function run() {
  await testFirebaseBearerCanLoadProfileAndUsePostcardRoutes();
  await testPreservedLegacyEmailReusesHistoricalAccountAcrossRepeatedSignIns();
  console.log("firebase auth profile contract: PASS");
}

run().catch((error) => {
  console.error("firebase auth profile contract: FAIL");
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
