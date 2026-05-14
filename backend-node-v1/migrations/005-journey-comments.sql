-- ============================================================
-- 17. journey_comments
--
-- One-on-one comment threads anchored to a journey. Threads are always
-- initiated by a viewer (friend) commenting on the owner's journey; both
-- sides then exchange messages. thread_key collapses (journey_id, sender,
-- recipient) so both endpoints address the same conversation.
-- ============================================================

CREATE TABLE IF NOT EXISTS journey_comments (
  id              TEXT PRIMARY KEY,
  journey_id      TEXT NOT NULL,
  owner_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sender_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recipient_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  thread_key      TEXT NOT NULL,
  content         TEXT NOT NULL,
  client_draft_id TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  read_at         TIMESTAMPTZ,
  deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_jc_thread
  ON journey_comments(thread_key, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_jc_recipient_unread
  ON journey_comments(recipient_id, journey_id)
  WHERE read_at IS NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_jc_owner_journey
  ON journey_comments(owner_id, journey_id, created_at DESC);

-- Idempotency: client may retry the same draft; we de-dupe on (sender, draft).
CREATE UNIQUE INDEX IF NOT EXISTS idx_jc_sender_draft
  ON journey_comments(sender_id, client_draft_id)
  WHERE client_draft_id IS NOT NULL;
