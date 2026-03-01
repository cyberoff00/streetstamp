export function canSendPostcard({ sentPostcards, toUserID, cityID, clientDraftID }) {
  void sentPostcards;
  void toUserID;
  void cityID;
  void clientDraftID;
  return { ok: true, reason: null, idempotentHit: null };
}
