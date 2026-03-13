import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import path from 'node:path';
import os from 'node:os';
import fs from 'node:fs/promises';

const SERVER_DIR = process.cwd();

async function waitForHealth(port) {
  const start = Date.now();
  while (Date.now() - start < 8000) {
    try {
      const resp = await fetch(`http://127.0.0.1:${port}/v1/health`);
      if (resp.ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 120));
  }
  throw new Error('server did not become healthy');
}

function startServer({ port, dataFile, mediaDir }) {
  return spawn('node', ['server.js'], {
    cwd: SERVER_DIR,
    env: {
      ...process.env,
      PORT: String(port),
      DATA_FILE: dataFile,
      MEDIA_DIR: mediaDir,
      MEDIA_PUBLIC_BASE: `http://127.0.0.1:${port}`,
      DATABASE_URL: ''
    },
    stdio: 'ignore'
  });
}

async function stopServer(child) {
  if (!child) return;
  if (child.exitCode !== null || child.signalCode !== null) return;
  child.kill('SIGTERM');
  await new Promise((resolve) => child.once('close', resolve));
}

async function requestJSON(port, method, pathName, token, body) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;

  const resp = await fetch(`http://127.0.0.1:${port}${pathName}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined
  });

  const data = await resp.json().catch(() => ({}));
  return { status: resp.status, data };
}

async function registerUser(port, email) {
  const resp = await requestJSON(port, 'POST', '/v1/auth/email/register', null, {
    email,
    password: 'password123'
  });
  assert.equal(resp.status, 200);
  return resp.data;
}

async function setupFriends(port) {
  const u1 = await registerUser(port, `u1_${Date.now()}@test.dev`);
  const u2 = await registerUser(port, `u2_${Date.now()}@test.dev`);

  const me2 = await requestJSON(port, 'GET', '/v1/profile/me', u2.accessToken);
  assert.equal(me2.status, 200);

  const sendReq = await requestJSON(port, 'POST', '/v1/friends/requests', u1.accessToken, {
    inviteCode: me2.data.inviteCode,
    displayName: 'friend2'
  });
  assert.equal(sendReq.status, 200);

  const incoming = await requestJSON(port, 'GET', '/v1/friends/requests', u2.accessToken);
  assert.equal(incoming.status, 200);
  const reqID = incoming.data.incoming?.[0]?.id;
  assert.ok(reqID);

  const accept = await requestJSON(port, 'POST', `/v1/friends/requests/${reqID}/accept`, u2.accessToken);
  assert.equal(accept.status, 200);

  return { u1, u2 };
}

async function run() {
  const port = 18123;
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'postcard-api-'));
  const dataFile = path.join(tmp, 'data.json');
  const mediaDir = path.join(tmp, 'media');
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
  }, null, 2), 'utf8');
  const child = startServer({ port, dataFile, mediaDir });

  try {
    await waitForHealth(port);
    const { u1, u2 } = await setupFriends(port);

    const send = await requestJSON(port, 'POST', '/v1/postcards/send', u1.accessToken, {
      clientDraftID: 'd1',
      toUserID: u2.userId,
      cityID: 'paris',
      cityJourneyCount: 2,
      cityName: 'Paris',
      messageText: 'hello postcard',
      photoURL: '/media/fake.jpg',
      allowedCityIDs: ['paris']
    });

    assert.equal(send.status, 200);
    assert.ok(send.data.messageID);

    const sent = await requestJSON(port, 'GET', '/v1/postcards?box=sent', u1.accessToken);
    assert.equal(sent.status, 200);
    assert.equal(Array.isArray(sent.data.items), true);
    assert.equal(sent.data.items.length, 1);
    assert.equal(sent.data.items[0].messageID, send.data.messageID);
    assert.equal(sent.data.items[0].photoURL, `http://127.0.0.1:${port}/media/fake.jpg`);
    assert.equal(sent.data.items[0].toDisplayName, 'Explorer');

    const received = await requestJSON(port, 'GET', '/v1/postcards?box=received', u2.accessToken);
    assert.equal(received.status, 200);
    assert.equal(Array.isArray(received.data.items), true);
    assert.equal(received.data.items.length, 1);
    assert.equal(received.data.items[0].messageID, send.data.messageID);
    assert.equal(received.data.items[0].photoURL, `http://127.0.0.1:${port}/media/fake.jpg`);
    assert.equal(received.data.items[0].toDisplayName, 'Explorer');

    const notifications = await requestJSON(port, 'GET', '/v1/notifications?unreadOnly=0', u2.accessToken);
    assert.equal(notifications.status, 200);
    const postcardNotice = (notifications.data.items || []).find((x) => x.type === 'postcard_received');
    assert.ok(postcardNotice, 'expected postcard_received notification');
    assert.equal(postcardNotice.cityID, 'paris');
    assert.equal(postcardNotice.cityName, 'Paris');
    assert.equal(postcardNotice.messageText, 'hello postcard');
    assert.equal(postcardNotice.photoURL, `http://127.0.0.1:${port}/media/fake.jpg`);

    const secondSend = await requestJSON(port, 'POST', '/v1/postcards/send', u1.accessToken, {
      clientDraftID: 'd2',
      toUserID: u2.userId,
      cityID: 'paris',
      cityJourneyCount: 2,
      cityName: 'Paris',
      messageText: 'second postcard',
      photoURL: '/media/fake.jpg',
      allowedCityIDs: ['paris']
    });

    assert.equal(secondSend.status, 200);
    assert.ok(secondSend.data.messageID);

    const thirdSend = await requestJSON(port, 'POST', '/v1/postcards/send', u1.accessToken, {
      clientDraftID: 'd3',
      toUserID: u2.userId,
      cityID: 'paris',
      cityJourneyCount: 2,
      cityName: 'Paris',
      messageText: 'third postcard',
      photoURL: '/media/fake.jpg',
      allowedCityIDs: ['paris']
    });

    assert.equal(thirdSend.status, 200);
    assert.ok(thirdSend.data.messageID);

    console.log('postcard API contract: PASS');
  } finally {
    await stopServer(child);
    await fs.rm(tmp, { recursive: true, force: true });
  }
}

run().catch((err) => {
  console.error('postcard API contract: FAIL');
  console.error(err && err.stack ? err.stack : err);
  process.exit(1);
});
