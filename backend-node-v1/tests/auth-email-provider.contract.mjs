import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import http from "node:http";
import path from "node:path";
import os from "node:os";
import fs from "node:fs/promises";

const SERVER_DIR = process.cwd();
const APP_PORT = 18235;
const STUB_PORT = 18236;

async function waitFor(check, label) {
  const start = Date.now();
  while (Date.now() - start < 8000) {
    try {
      if (await check()) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`${label} did not become ready`);
}

async function waitForHealth(port) {
  await waitFor(async () => {
    const resp = await fetch(`http://127.0.0.1:${port}/v1/health`);
    return resp.ok;
  }, "app server");
}

function startServer({ port, dataFile, mediaDir, resendBase }) {
  return spawn("node", ["server.js"], {
    cwd: SERVER_DIR,
    env: {
      ...process.env,
      PORT: String(port),
      DATA_FILE: dataFile,
      MEDIA_DIR: mediaDir,
      MEDIA_PUBLIC_BASE: `http://127.0.0.1:${port}`,
      DATABASE_URL: "",
      RESEND_API_KEY: "re_test_123",
      RESEND_FROM_EMAIL: "StreetStamps <auth@streetstamps.example>",
      RESEND_API_BASE: resendBase
    },
    stdio: "ignore"
  });
}

async function stopProcess(child) {
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
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "auth-email-provider-"));
  const dataFile = path.join(tmp, "data.json");
  const mediaDir = path.join(tmp, "media");
  await fs.writeFile(dataFile, JSON.stringify({
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
  }, null, 2), "utf8");

  const seenRequests = [];
  const stub = http.createServer((req, res) => {
    let body = "";
    req.on("data", (chunk) => { body += String(chunk); });
    req.on("end", () => {
      seenRequests.push({
        method: req.method,
        url: req.url,
        authorization: req.headers.authorization || "",
        contentType: req.headers["content-type"] || "",
        body: body ? JSON.parse(body) : null
      });
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ id: "email_mock_1" }));
    });
  });

  await new Promise((resolve) => stub.listen(STUB_PORT, "127.0.0.1", resolve));
  const child = startServer({
    port: APP_PORT,
    dataFile,
    mediaDir,
    resendBase: `http://127.0.0.1:${STUB_PORT}`
  });

  try {
    await waitForHealth(APP_PORT);

    const created = await requestJSON(APP_PORT, "POST", "/v1/auth/register", {
      email: "resend-user@example.com",
      password: "Password1!"
    });
    assert.equal(created.status, 200);

    await waitFor(() => seenRequests.length === 1, "resend stub");
    assert.equal(seenRequests[0].method, "POST");
    assert.equal(seenRequests[0].url, "/emails");
    assert.equal(seenRequests[0].authorization, "Bearer re_test_123");
    assert.equal(seenRequests[0].contentType, "application/json");
    assert.equal(seenRequests[0].body.from, "StreetStamps <auth@streetstamps.example>");
    assert.deepEqual(seenRequests[0].body.to, ["resend-user@example.com"]);
    assert.match(seenRequests[0].body.subject, /Verify/i);
    assert.match(seenRequests[0].body.text, /verify-email\?token=/i);

    console.log("auth email provider contract: PASS");
  } finally {
    await stopProcess(child);
    await new Promise((resolve) => stub.close(resolve));
    await fs.rm(tmp, { recursive: true, force: true });
  }
}

run().catch((error) => {
  console.error("auth email provider contract: FAIL");
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
