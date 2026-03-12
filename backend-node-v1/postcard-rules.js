function normalizeText(value) {
  return String(value || '').trim();
}

function normalizeKey(value) {
  return normalizeText(value).toLowerCase();
}

function toUserIDOf(item) {
  return normalizeText(item?.toUserID || item?.toUserId);
}

function cityIDOf(item) {
  return normalizeText(item?.cityID || item?.cityId);
}

function clientDraftIDOf(item) {
  return normalizeText(item?.clientDraftID || item?.clientDraftId);
}

function statusOf(item) {
  return normalizeKey(item?.status || 'sent');
}

function canSendPostcard({ sentPostcards, toUserID, cityID, clientDraftID, allowedCityIDs }) {
  const all = Array.isArray(sentPostcards) ? sentPostcards : [];
  const normalizedDraftID = normalizeText(clientDraftID);

  if (normalizedDraftID) {
    const hit = all.find((item) => {
      return statusOf(item) === 'sent' && clientDraftIDOf(item) === normalizedDraftID;
    });
    if (hit) {
      return { ok: true, reason: null, idempotentHit: hit };
    }
  }

  const normalizedCityID = normalizeText(cityID);
  const normalizedToUserID = normalizeText(toUserID);

  const allowed = Array.isArray(allowedCityIDs)
    ? new Set(allowedCityIDs.map((x) => normalizeText(x)).filter(Boolean))
    : null;

  if (allowed && allowed.size > 0 && !allowed.has(normalizedCityID)) {
    return { ok: false, reason: 'city_not_allowed', idempotentHit: null };
  }

  const sentOnly = all.filter((item) => statusOf(item) === 'sent');

  const sameFriendSameCityCount = sentOnly.filter((item) => {
    return cityIDOf(item) === normalizedCityID && toUserIDOf(item) === normalizedToUserID;
  }).length;
  if (sameFriendSameCityCount >= 2) {
    return { ok: false, reason: 'city_friend_quota_exceeded', idempotentHit: null };
  }

  const uniqueFriendCountForCity = new Set(
    sentOnly
      .filter((item) => cityIDOf(item) === normalizedCityID)
      .map((item) => toUserIDOf(item))
      .filter(Boolean)
  ).size;
  if (uniqueFriendCountForCity >= 10 && sameFriendSameCityCount === 0) {
    return { ok: false, reason: 'city_total_quota_exceeded', idempotentHit: null };
  }

  return { ok: true, reason: null, idempotentHit: null };
}

module.exports = { canSendPostcard };
