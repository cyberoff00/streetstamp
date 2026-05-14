-- Coins: account-user authoritative balance lives in users.coins.
-- Guest users keep their coins in iOS UserDefaults (not synced here).
-- Membership stays in RevenueCat (no change).

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS coins INTEGER NOT NULL DEFAULT 0
  CHECK (coins >= 0);

-- Idempotency for coin merges from external sources.
-- Three sources feed in: guest→account upgrade, device-to-device transfer,
-- one-shot UserDefaults→Postgres migration on first account-user launch
-- of the new app version. Each merge call carries a stable token; second
-- attempt with the same token is a no-op so retries can't double-credit.
CREATE TABLE IF NOT EXISTS coin_merge_tokens (
  token       TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount      INTEGER NOT NULL,
  source      TEXT NOT NULL,   -- 'guest_upgrade' | 'device_transfer' | 'userdefaults_migration'
  applied_at  BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_coin_merge_user ON coin_merge_tokens(user_id);

-- Audit trail for every coin movement (grant / spend / merge / admin).
-- Append-only. Lets us answer "why did this user's balance change" months
-- later when a customer asks. Not on the hot read path.
CREATE TABLE IF NOT EXISTS coin_transactions (
  id          BIGSERIAL PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  delta       INTEGER NOT NULL,        -- positive = grant, negative = spend
  balance_after INTEGER NOT NULL,
  source      TEXT NOT NULL,           -- 'grant' | 'spend' | 'merge' | 'admin_grant'
  reason      TEXT NOT NULL DEFAULT '',
  merge_token TEXT,                    -- set when source='merge'
  created_at  BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_coin_tx_user_time ON coin_transactions(user_id, created_at DESC);
