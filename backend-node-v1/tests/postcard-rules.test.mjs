import test from 'node:test';
import assert from 'node:assert/strict';
import { canSendPostcard } from '../postcard-rules.js';

test('rejects duplicate city->same friend', () => {
  const sent = [{ toUserID: 'u2', cityID: 'paris', status: 'sent' }];
  const result = canSendPostcard({
    sentPostcards: sent,
    toUserID: 'u2',
    cityID: 'paris',
    clientDraftID: 'd2'
  });

  assert.equal(result.ok, false);
  assert.equal(result.reason, 'city_friend_quota_exceeded');
});
