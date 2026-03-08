import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { canSendPostcard } = require('../postcard-rules.js');

test('rejects duplicate city->same friend', () => {
  const sent = [{ toUserID: 'u2', cityID: 'paris', status: 'sent' }];
  const result = canSendPostcard({
    sentPostcards: sent,
    toUserID: 'u2',
    cityID: 'paris',
    clientDraftID: 'd2',
    allowedCityIDs: ['paris', 'tokyo']
  });

  assert.equal(result.ok, false);
  assert.equal(result.reason, 'city_friend_quota_exceeded');
});

test('rejects city total above 5', () => {
  const sent = [1, 2, 3, 4, 5].map((n) => ({
    toUserID: `u${n}`,
    cityID: 'paris',
    status: 'sent',
    clientDraftID: `d${n}`
  }));

  const result = canSendPostcard({
    sentPostcards: sent,
    toUserID: 'u6',
    cityID: 'paris',
    clientDraftID: 'd6',
    allowedCityIDs: ['paris']
  });

  assert.equal(result.ok, false);
  assert.equal(result.reason, 'city_total_quota_exceeded');
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
