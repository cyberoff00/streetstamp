import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import jwt from "jsonwebtoken";

const SERVER_DIR = process.cwd();
const JWT_SECRET = "change-me-in-production";
let nextPort = 18155;

function defaultLoadout() {
  return {
    bodyId: "body",
    headId: "head",
    hairId: "hair_0001",
    suitId: null,
    upperId: "upper_0001",
    underId: "under_0001",
    savedUpperIdForSuit: "upper_0001",
    savedUnderIdForSuit: "under_0001",
    accessoryIds: [],
    expressionId: "expr_0001",
    hairColorHex: "#2B2A28",
    bodyColorHex: "#E8BE9C"
  };
}

function makeUser(id) {
  return {
    id,
    provider: "password",
    email: `${id}@example.com`,
    passwordHash: null,
    inviteCode: `INV${id.slice(-5).toUpperCase()}`,
    handle: id.slice(0, 24),
    handleChangeUsed: false,
    profileVisibility: "friendsOnly",
    displayName: "Explorer",
    bio: "",
    loadout: defaultLoadout(),
    journeys: [],
    cityCards: [],
    friendIDs: [],
    notifications: [],
    sentPostcards: [],
    receivedPostcards: [],
    createdAt: 1771000000
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
  throw new Error(`server did not become healthy\n${logs}`);
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

async function startServer(db) {
  const port = nextPort;
  nextPort += 1;

  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "loadout-hat-glass-"));
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
      FIREBASE_AUTH_ENABLED: "0"
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

test("profile loadout patch preserves hat and glass selections", async () => {
  const userID = "u_loadout_hat_001";
  const token = jwt.sign(
    { uid: userID, prv: "password", typ: "access", sid: "sid-hat-glass" },
    JWT_SECRET,
    { expiresIn: "2h" }
  );
  const db = {
    users: { [userID]: makeUser(userID) },
    emailIndex: { [`${userID}@example.com`]: userID },
    inviteIndex: {},
    oauthIndex: {},
    firebaseIdentityIndex: {},
    handleIndex: { [userID.slice(0, 24)]: userID },
    likesIndex: {},
    friendRequestsIndex: {},
    postcardsIndex: {}
  };

  const server = await startServer(db);
  try {
    const requestedLoadout = {
      ...defaultLoadout(),
      hatId: "hat_004",
      glassId: "glass_006",
      accessoryIds: ["acc_002"]
    };

    const response = await requestJSON(
      server.port,
      "PATCH",
      "/v1/profile/loadout",
      token,
      { loadout: requestedLoadout }
    );

    assert.equal(response.status, 200);
    assert.equal(response.data.loadout?.hatId, "hat_004");
    assert.equal(response.data.loadout?.glassId, "glass_006");
    assert.deepEqual(response.data.loadout?.accessoryIds, ["acc_002"]);

    const persisted = (await server.readDB()).users[userID].loadout;
    assert.equal(persisted.hatId, "hat_004");
    assert.equal(persisted.glassId, "glass_006");
    assert.deepEqual(persisted.accessoryIds, ["acc_002"]);
  } finally {
    await server.cleanup();
  }
});
