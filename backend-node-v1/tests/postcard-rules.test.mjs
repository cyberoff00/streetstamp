import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { canSendPostcard } = require('../postcard-rules.js');

test('allows up to two postcards to the same friend from the same city and rejects the third', () => {
  const sent = [
    { toUserID: 'u2', cityID: 'paris', status: 'sent', clientDraftID: 'd1' },
    { toUserID: 'u2', cityID: 'paris', status: 'sent', clientDraftID: 'd2' }
  ];
  const result = canSendPostcard({
    sentPostcards: sent,
    toUserID: 'u2',
    cityID: 'paris',
    clientDraftID: 'd3',
    allowedCityIDs: ['paris', 'tokyo']
  });

  assert.equal(result.ok, false);
  assert.equal(result.reason, 'city_friend_quota_exceeded');
});

test('an additional journey increases the same-city per-friend quota by one', () => {
  const sent = [
    { toUserID: 'u2', cityID: 'paris', status: 'sent', clientDraftID: 'd1' },
    { toUserID: 'u2', cityID: 'paris', status: 'sent', clientDraftID: 'd2' }
  ];

  const result = canSendPostcard({
    sentPostcards: sent,
    toUserID: 'u2',
    cityID: 'paris',
    cityJourneyCount: 2,
    clientDraftID: 'd3',
    allowedCityIDs: ['paris']
  });

  assert.equal(result.ok, true);
  assert.equal(result.reason, null);
});

test('rejects city total above 10', () => {
  const sent = Array.from({ length: 10 }, (_, index) => index + 1).map((n) => ({
    toUserID: `u${n}`,
    cityID: 'paris',
    status: 'sent',
    clientDraftID: `d${n}`
  }));

  const result = canSendPostcard({
    sentPostcards: sent,
    toUserID: 'u11',
    cityID: 'paris',
    clientDraftID: 'd11',
    allowedCityIDs: ['paris']
  });

  assert.equal(result.ok, false);
  assert.equal(result.reason, 'city_total_quota_exceeded');
});

test('an additional journey increases the same-city unique friend quota by ten', () => {
  const sent = Array.from({ length: 10 }, (_, index) => index + 1).map((n) => ({
    toUserID: `u${n}`,
    cityID: 'paris',
    status: 'sent',
    clientDraftID: `d${n}`
  }));

  const result = canSendPostcard({
    sentPostcards: sent,
    toUserID: 'u11',
    cityID: 'paris',
    cityJourneyCount: 2,
    clientDraftID: 'd11',
    allowedCityIDs: ['paris']
  });

  assert.equal(result.ok, true);
  assert.equal(result.reason, null);
});

test('second postcard to an existing friend does not consume a new city friend slot', () => {
  const sent = Array.from({ length: 10 }, (_, index) => index + 1).map((n) => ({
    toUserID: `u${n}`,
    cityID: 'paris',
    status: 'sent',
    clientDraftID: `d${n}`
  }));

  const result = canSendPostcard({
    sentPostcards: sent,
    toUserID: 'u1',
    cityID: 'paris',
    clientDraftID: 'd11',
    allowedCityIDs: ['paris']
  });

  assert.equal(result.ok, true);
  assert.equal(result.reason, null);
});

test('second postcard to the same friend from the same city is still allowed', () => {
  const sent = [{ toUserID: 'u2', cityID: 'paris', status: 'sent', clientDraftID: 'd1' }];

  const result = canSendPostcard({
    sentPostcards: sent,
    toUserID: 'u2',
    cityID: 'paris',
    clientDraftID: 'd2',
    allowedCityIDs: ['paris']
  });

  assert.equal(result.ok, true);
  assert.equal(result.reason, null);
});

test('failed items do not count for quota', () => {
  const sent = [{ toUserID: 'u2', cityID: 'paris', status: 'failed', clientDraftID: 'd1' }];

  const result = canSendPostcard({
    sentPostcards: sent,
    toUserID: 'u2',
    cityID: 'paris',
    clientDraftID: 'd2',
    allowedCityIDs: ['paris']
  });

  assert.equal(result.ok, true);
  assert.equal(result.reason, null);
});

test('returns idempotent hit on same clientDraftID', () => {
  const sent = [{
    messageID: 'm1',
    toUserID: 'u2',
    cityID: 'paris',
    status: 'sent',
    clientDraftID: 'd1'
  }];

  const result = canSendPostcard({
    sentPostcards: sent,
    toUserID: 'u2',
    cityID: 'paris',
    clientDraftID: 'd1',
    allowedCityIDs: ['paris']
  });

  assert.equal(result.ok, true);
  assert.equal(result.reason, null);
  assert.equal(result.idempotentHit.messageID, 'm1');
});

test('rejects city that is not in allowedCityIDs', () => {
  const result = canSendPostcard({
    sentPostcards: [],
    toUserID: 'u2',
    cityID: 'london',
    clientDraftID: 'd1',
    allowedCityIDs: ['paris']
  });

  assert.equal(result.ok, false);
  assert.equal(result.reason, 'city_not_allowed');
});
