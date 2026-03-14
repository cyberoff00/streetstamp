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
  const u1 = await registerUser(port, `journey_u1_${Date.now()}@test.dev`);
  const u2 = await registerUser(port, `journey_u2_${Date.now()}@test.dev`);

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

function makeJourney(id, visibility = 'friendsOnly') {
  return {
    id,
    title: `Journey ${id}`,
    cityID: 'paris|fr',
    distance: 3200,
    startTime: '2026-03-07T10:00:00.000Z',
    endTime: '2026-03-07T11:00:00.000Z',
    visibility,
    routeCoordinates: [
      { lat: 48.8566, lon: 2.3522 },
      { lat: 48.857, lon: 2.353 }
    ],
    memories: []
  };
}

async function fetchFriendProfile(port, accessToken, userID) {
  const resp = await requestJSON(port, 'GET', `/v1/profile/${userID}`, accessToken);
  assert.equal(resp.status, 200);
  return resp.data;
}

async function migrateJourneys(port, accessToken, body) {
  const resp = await requestJSON(port, 'POST', '/v1/journeys/migrate', accessToken, body);
  assert.equal(resp.status, 200);
  return resp.data;
}

async function run() {
  const port = 18124;
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'journey-migrate-'));
  const dataFile = path.join(tmp, 'data.json');
  const mediaDir = path.join(tmp, 'media');
  const child = startServer({ port, dataFile, mediaDir });

  try {
    await waitForHealth(port);
    const { u1, u2 } = await setupFriends(port);

    await migrateJourneys(port, u1.accessToken, {
      journeys: [makeJourney('j_a'), makeJourney('j_c')],
      unlockedCityCards: [{ id: 'paris', name: 'Paris', countryISO2: 'FR' }]
    });

    const initialProfile = await fetchFriendProfile(port, u2.accessToken, u1.userId);
    assert.deepEqual(
      initialProfile.journeys.map((x) => x.id).sort(),
      ['j_a', 'j_c']
    );
    assert.deepEqual(
      initialProfile.journeys.map((x) => x.cityID),
      ['paris|fr', 'paris|fr']
    );
    assert.deepEqual(
      initialProfile.unlockedCityCards.map((x) => x.id).sort(),
      ['paris']
    );

    await migrateJourneys(port, u1.accessToken, {
      journeys: [makeJourney('j_b')],
      unlockedCityCards: [],
      removedJourneyIDs: [],
      snapshotComplete: false
    });

    const mergedProfile = await fetchFriendProfile(port, u2.accessToken, u1.userId);
    assert.deepEqual(
      mergedProfile.journeys.map((x) => x.id).sort(),
      ['j_a', 'j_b', 'j_c'],
      'partial migration should preserve previously shared journeys'
    );
    assert.deepEqual(
      mergedProfile.unlockedCityCards.map((x) => x.id).sort(),
      ['paris'],
      'partial migration should preserve previously shared city cards'
    );

    await migrateJourneys(port, u1.accessToken, {
      journeys: [makeJourney('j_b')],
      unlockedCityCards: [],
      removedJourneyIDs: ['j_a'],
      snapshotComplete: false
    });

    const selectiveRemovalProfile = await fetchFriendProfile(port, u2.accessToken, u1.userId);
    assert.deepEqual(
      selectiveRemovalProfile.journeys.map((x) => x.id).sort(),
      ['j_b', 'j_c'],
      'partial migration should only remove journeys explicitly listed in removedJourneyIDs'
    );

    console.log('journey migrate contract: PASS');
  } finally {
    await stopServer(child);
    await fs.rm(tmp, { recursive: true, force: true });
  }
}

run().catch((err) => {
  console.error('journey migrate contract: FAIL');
  console.error(err && err.stack ? err.stack : err);
  process.exit(1);
});
