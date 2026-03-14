import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import path from "node:path";
import os from "node:os";
import fs from "node:fs/promises";

const SERVER_DIR = process.cwd();
const PORT = 18230;

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

function startServer({ port, dataFile, mediaDir, outboxFile }) {
  return spawn("node", ["server.js"], {
    cwd: SERVER_DIR,
    env: {
      ...process.env,
      PORT: String(port),
      DATA_FILE: dataFile,
      MEDIA_DIR: mediaDir,
      MEDIA_PUBLIC_BASE: `http://127.0.0.1:${port}`,
      DATABASE_URL: "",
      TEST_EMAIL_OUTBOX_FILE: outboxFile
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

async function requestJSON(port, method, pathName, body) {
  const resp = await fetch(`http://127.0.0.1:${port}${pathName}`, {
    method,
    headers: { "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined
  });
  const data = await resp.json().catch(() => ({}));
  return { status: resp.status, data };
}

async function readOutbox(outboxFile) {
  try {
    return JSON.parse(await fs.readFile(outboxFile, "utf8"));
  } catch (error) {
    if (error && error.code === "ENOENT") return [];
    throw error;
  }
}

async function run() {
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "auth-register-"));
  const dataFile = path.join(tmp, "data.json");
  const mediaDir = path.join(tmp, "media");
  const outboxFile = path.join(tmp, "outbox.json");
  await fs.writeFile(dataFile, JSON.stringify({
    users: {
      u_legacy163: {
        id: "u_legacy163",
        provider: "email",
        email: "yinterestingy@163.com",
        passwordHash: "legacy-hash",
        inviteCode: "LEGACY163",
        handle: "legacy163",
        handleChangeUsed: false,
        profileVisibility: "friends_only",
        displayName: "Legacy 163",
        profileSetupCompleted: true,
        bio: "Legacy account",
        loadout: {},
        journeys: [],
        cityCards: [],
        friendIDs: [],
        notifications: [],
        sentPostcards: [],
        receivedPostcards: [],
        createdAt: 1
      }
    },
    emailIndex: {
      "yinterestingy@163.com": "u_legacy163"
    },
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
  }, null, 2), "utf8");

  const child = startServer({ port: PORT, dataFile, mediaDir, outboxFile });

  try {
    await waitForHealth(PORT);

    const missingLetter = await requestJSON(PORT, "POST", "/v1/auth/register", {
      email: "missing-letter@example.com",
      password: "12345678!"
    });
    assert.equal(missingLetter.status, 400);
    assert.equal((await readOutbox(outboxFile)).length, 0);

    const missingNumber = await requestJSON(PORT, "POST", "/v1/auth/register", {
      email: "missing-number@example.com",
      password: "Password!"
    });
    assert.equal(missingNumber.status, 400);
    assert.equal((await readOutbox(outboxFile)).length, 0);

    const missingSpecial = await requestJSON(PORT, "POST", "/v1/auth/register", {
      email: "missing-special@example.com",
      password: "Password1"
    });
    assert.equal(missingSpecial.status, 400);
    assert.equal((await readOutbox(outboxFile)).length, 0);

    const good = await requestJSON(PORT, "POST", "/v1/auth/register", {
      email: "valid@example.com",
      password: "Password1!",
      displayName: "Valid User"
    });
    assert.equal(good.status, 200);
    assert.equal(good.data.emailVerificationRequired, true);
    assert.equal(typeof good.data.userId, "string");
    assert.equal(good.data.needsProfileSetup, true);
    assert.equal((await readOutbox(outboxFile)).length, 1);

    const duplicate = await requestJSON(PORT, "POST", "/v1/auth/register", {
      email: "valid@example.com",
      password: "Password1!"
    });
    assert.equal(duplicate.status, 200);
    assert.equal(duplicate.data.userId, good.data.userId);
    assert.equal(duplicate.data.emailVerificationRequired, true);
    assert.equal((await readOutbox(outboxFile)).length, 2);

    const recoveredLegacy = await requestJSON(PORT, "POST", "/v1/auth/register", {
      email: "yinterestingy@163.com",
      password: "Password1!",
      displayName: "Recovered User"
    });
    assert.equal(recoveredLegacy.status, 200);
    assert.equal(recoveredLegacy.data.emailVerificationRequired, true);

    const state = JSON.parse(await fs.readFile(dataFile, "utf8"));
    const identity = Object.values(state.authIdentities).find((item) => item.email === "valid@example.com");
    assert.ok(identity, "expected email_password identity to be persisted");
    assert.equal(identity.provider, "email_password");
    assert.equal(identity.emailVerified, false);

    const recoveredIdentity = Object.values(state.authIdentities).find((item) => item.email === "yinterestingy@163.com");
    assert.ok(recoveredIdentity, "expected recovered legacy email identity to be persisted");
    assert.equal(recoveredIdentity.provider, "email_password");
    assert.equal(recoveredIdentity.emailVerified, false);
    assert.equal(state.emailIndex["yinterestingy@163.com"], recoveredLegacy.data.userId);

    const createdUser = state.users[good.data.userId];
    assert.ok(createdUser, "expected registered user to be persisted");
    assert.equal(createdUser.profileSetupCompleted, false);

    const recoveredUser = state.users[recoveredLegacy.data.userId];
    assert.ok(recoveredUser, "expected recovered legacy user to be persisted");
    assert.equal(recoveredUser.displayName, "Recovered User");

    console.log("auth register contract: PASS");
  } finally {
    await stopServer(child);
    await fs.rm(tmp, { recursive: true, force: true });
  }
}

run().catch((error) => {
  console.error("auth register contract: FAIL");
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
