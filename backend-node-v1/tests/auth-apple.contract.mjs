import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import path from "node:path";
import os from "node:os";
import fs from "node:fs/promises";

const SERVER_DIR = process.cwd();
const PORT = 18234;

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

function startServer({ port, dataFile, mediaDir, fixtures }) {
  return spawn("node", ["server.js"], {
    cwd: SERVER_DIR,
    env: {
      ...process.env,
      PORT: String(port),
      DATA_FILE: dataFile,
      MEDIA_DIR: mediaDir,
      MEDIA_PUBLIC_BASE: `http://127.0.0.1:${port}`,
      DATABASE_URL: "",
      TEST_APPLE_OAUTH_FIXTURES: JSON.stringify(fixtures)
    },
    stdio: ["ignore", "pipe", "pipe"]
  });
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

async function run() {
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "auth-apple-"));
  const dataFile = path.join(tmp, "data.json");
  const mediaDir = path.join(tmp, "media");
  await fs.writeFile(dataFile, JSON.stringify({
    users: {},
    emailIndex: {
      "existing@example.com": "u_existing_email"
    },
    inviteIndex: {
      KEEP1111: "u_existing_email"
    },
    oauthIndex: {},
    authIdentities: {
      "aid_existing_email": {
        id: "aid_existing_email",
        userID: "u_existing_email",
        provider: "email_password",
        providerSubject: "existing@example.com",
        email: "existing@example.com",
        emailVerified: true,
        passwordHash: "hashed",
        createdAt: 1773000000,
        updatedAt: 1773000000
      }
    },
    emailVerificationTokens: {},
    passwordResetTokens: {},
    refreshTokens: {},
    handleIndex: {
      email_owner: "u_existing_email"
    },
    likesIndex: {},
    friendRequestsIndex: {},
    postcardsIndex: {},
    users: {
      "u_existing_email": {
        id: "u_existing_email",
        provider: "email",
        email: "existing@example.com",
        passwordHash: "hashed",
        inviteCode: "KEEP1111",
        handle: "email_owner",
        handleChangeUsed: false,
        profileVisibility: "friendsOnly",
        displayName: "Existing Email Owner",
        bio: "Travel Enthusiastic",
        loadout: {
          species: "boy",
          color: "yellow",
          accessory: null,
          headgear: null,
          handheld: null
        },
        journeys: [
          {
            id: "j_existing",
            title: "Saved journey",
            distance: 42,
            startTime: "2026-03-01T00:00:00.000Z",
            endTime: "2026-03-01T01:00:00.000Z",
            visibility: "friendsOnly",
            routeCoordinates: [],
            memories: []
          }
        ],
        cityCards: [],
        friendIDs: [],
        notifications: [],
        sentPostcards: [],
        receivedPostcards: [],
        createdAt: 1773000000
      }
    }
  }, null, 2), "utf8");

  const fixtures = {
    "apple-first-token": {
      sub: "apple-user-first",
      email: "apple-fresh@example.com",
      email_verified: true
    },
    "apple-existing-token": {
      sub: "apple-user-first",
      email: "apple-fresh@example.com",
      email_verified: true
    },
    "apple-merge-token": {
      sub: "apple-user-merge",
      email: "existing@example.com",
      email_verified: true
    },
    "apple-hidden-token": {
      sub: "apple-user-hidden",
      email: "abc123@privaterelay.appleid.com",
      email_verified: true
    }
  };

  const child = startServer({ port: PORT, dataFile, mediaDir, fixtures });
  let logs = "";
  child.stdout?.on("data", (chunk) => { logs += String(chunk); });
  child.stderr?.on("data", (chunk) => { logs += String(chunk); });

  try {
    await waitForHealth(PORT, () => logs);

    const firstLogin = await requestJSON(PORT, "POST", "/v1/auth/apple", {
      idToken: "apple-first-token"
    });
    assert.equal(firstLogin.status, 200);
    assert.equal(firstLogin.data.provider, "apple");
    assert.equal(firstLogin.data.email, "apple-fresh@example.com");
    assert.equal(firstLogin.data.needsProfileSetup, true);
    const firstUserID = firstLogin.data.userId;
    assert.ok(firstUserID);

    const repeatedLogin = await requestJSON(PORT, "POST", "/v1/auth/apple", {
      idToken: "apple-existing-token"
    });
    assert.equal(repeatedLogin.status, 200);
    assert.equal(repeatedLogin.data.userId, firstUserID);
    assert.equal(repeatedLogin.data.needsProfileSetup, true);

    const mergedLogin = await requestJSON(PORT, "POST", "/v1/auth/apple", {
      idToken: "apple-merge-token"
    });
    assert.equal(mergedLogin.status, 200);
    assert.equal(mergedLogin.data.userId, "u_existing_email");
    assert.equal(mergedLogin.data.needsProfileSetup, false);

    const hiddenLogin = await requestJSON(PORT, "POST", "/v1/auth/apple", {
      idToken: "apple-hidden-token"
    });
    assert.equal(hiddenLogin.status, 200);
    assert.notEqual(hiddenLogin.data.userId, "u_existing_email");
    assert.equal(hiddenLogin.data.needsProfileSetup, true);

    const saved = JSON.parse(await fs.readFile(dataFile, "utf8"));
    const createdAppleIdentity = Object.values(saved.authIdentities).find((item) => (
      item.provider === "apple" && item.providerSubject === "apple-user-first"
    ));
    assert.ok(createdAppleIdentity, "expected apple identity for first-time login");
    assert.equal(createdAppleIdentity.userID, firstUserID);

    const mergedAppleIdentity = Object.values(saved.authIdentities).find((item) => (
      item.provider === "apple" && item.providerSubject === "apple-user-merge"
    ));
    assert.ok(mergedAppleIdentity, "expected apple identity for merged email login");
    assert.equal(mergedAppleIdentity.userID, "u_existing_email");

    const hiddenAppleIdentity = Object.values(saved.authIdentities).find((item) => (
      item.provider === "apple" && item.providerSubject === "apple-user-hidden"
    ));
    assert.ok(hiddenAppleIdentity, "expected apple identity for hidden relay login");
    assert.notEqual(hiddenAppleIdentity.userID, "u_existing_email");

    assert.equal(saved.users.u_existing_email.journeys.length, 1);
    assert.equal(saved.users[firstUserID].profileSetupCompleted, false);
    assert.equal(saved.users.u_existing_email.profileSetupCompleted, true);

    console.log("auth apple contract: PASS");
  } finally {
    await stopServer(child);
    await fs.rm(tmp, { recursive: true, force: true });
  }
}

run().catch((error) => {
  console.error("auth apple contract: FAIL");
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
