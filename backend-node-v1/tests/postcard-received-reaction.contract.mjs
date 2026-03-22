import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";

const SERVER_DIR = process.cwd();
const PORT = 18157;

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

async function waitForHealth(port, getLogs) {
  const start = Date.now();
  while (Date.now() - start < 8000) {
    try {
      const resp = await fetch(`http://127.0.0.1:${port}/v1/health`);
      if (resp.ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 120));
  }
  throw new Error(`server did not become healthy\n${getLogs?.() || ""}`);
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

async function stopServer(child) {
  if (!child) return;
  if (child.exitCode !== null || child.signalCode !== null) return;
  child.kill("SIGTERM");
  await new Promise((resolve) => child.once("close", resolve));
}

async function run() {
  const senderID = "u_postcard_sender";
  const receiverID = "u_postcard_receiver";
  const senderToken = "firebase-postcard-sender-token";
  const receiverToken = "firebase-postcard-receiver-token";

  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "postcard-received-reaction-"));
  const dataFile = path.join(tmp, "data.json");
  const mediaDir = path.join(tmp, "media");
  const db = {
    users: {
      [senderID]: makeUser(senderID, {
        provider: "google",
        email: "sender@test.dev",
        displayName: "Sender",
        friendIDs: [receiverID]
      }),
      [receiverID]: makeUser(receiverID, {
        provider: "password",
        email: "receiver@test.dev",
        displayName: "Receiver",
        friendIDs: [senderID]
      })
    },
    emailIndex: {
      "sender@test.dev": senderID,
      "receiver@test.dev": receiverID
    },
    inviteIndex: {},
    oauthIndex: {},
    firebaseIdentityIndex: {},
    handleIndex: {},
    likesIndex: {},
    friendRequestsIndex: {},
    postcardsIndex: {}
  };
  await fs.writeFile(dataFile, JSON.stringify(db, null, 2), "utf8");
  await fs.mkdir(mediaDir, { recursive: true });

  const fixtures = {
    [senderToken]: {
      uid: "firebase-postcard-sender",
      email: "sender@test.dev",
      email_verified: true,
      firebase: { sign_in_provider: "google.com" }
    },
    [receiverToken]: {
      uid: "firebase-postcard-receiver",
      email: "receiver@test.dev",
      email_verified: true,
      firebase: { sign_in_provider: "password" }
    }
  };

  const child = spawn("node", ["server.js"], {
    cwd: SERVER_DIR,
    env: {
      ...process.env,
      PORT: String(PORT),
      DATA_FILE: dataFile,
      MEDIA_DIR: mediaDir,
      MEDIA_PUBLIC_BASE: `http://127.0.0.1:${PORT}`,
      DATABASE_URL: "",
      FIREBASE_AUTH_ENABLED: "1",
      FIREBASE_PROJECT_ID: "streetstamps-firebase-tests",
      FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({ project_id: "streetstamps-firebase-tests" }),
      FIREBASE_LEGACY_APP_USER_ID: "u_legacy_preserved",
      TEST_FIREBASE_AUTH_FIXTURES: JSON.stringify(fixtures)
    },
    stdio: ["ignore", "pipe", "pipe"]
  });

  let logs = "";
  child.stdout?.on("data", (chunk) => { logs += String(chunk); });
  child.stderr?.on("data", (chunk) => { logs += String(chunk); });

  try {
    await waitForHealth(PORT, () => logs);

    const send = await requestJSON(PORT, "POST", "/v1/postcards/send", senderToken, {
      clientDraftID: "received-reaction-draft",
      toUserID: receiverID,
      cityID: "paris",
      cityJourneyCount: 1,
      cityName: "Paris",
      messageText: "hello postcard",
      photoURL: "/media/fake.jpg",
      allowedCityIDs: ["paris"]
    });
    assert.equal(send.status, 200);
    assert.ok(send.data.messageID);

    const react = await requestJSON(
      PORT,
      "POST",
      `/v1/postcards/${send.data.messageID}/react`,
      receiverToken,
      { reactionEmoji: "❤️", comment: "reply from receiver" }
    );
    assert.equal(react.status, 200);
    assert.equal(react.data.reaction?.comment, "reply from receiver");

    const received = await requestJSON(PORT, "GET", "/v1/postcards?box=received", receiverToken);
    assert.equal(received.status, 200);
    assert.equal(received.data.items.length, 1);
    assert.equal(received.data.items[0].messageID, send.data.messageID);
    assert.equal(received.data.items[0].reaction?.comment, "reply from receiver");
    assert.equal(received.data.items[0].reaction?.reactionEmoji, "❤️");

    console.log("postcard received reaction contract: PASS");
  } finally {
    await stopServer(child);
    await fs.rm(tmp, { recursive: true, force: true });
  }
}

run().catch((err) => {
  console.error("postcard received reaction contract: FAIL");
  console.error(err && err.stack ? err.stack : err);
  process.exit(1);
});
