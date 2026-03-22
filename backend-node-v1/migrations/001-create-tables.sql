-- StreetStamps: JSON blob → relational tables
-- Run AFTER backing up: pg_dump streetstamps > backup_before_migration.sql

BEGIN;

-- ============================================================
-- 1. users
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
  id              TEXT PRIMARY KEY,
  email           TEXT,
  display_name    TEXT NOT NULL DEFAULT 'Explorer',
  handle          TEXT,
  invite_code     TEXT,
  profile_visibility TEXT NOT NULL DEFAULT 'friendsOnly',
  profile_setup_completed BOOLEAN NOT NULL DEFAULT false,
  handle_change_used BOOLEAN NOT NULL DEFAULT false,
  bio             TEXT NOT NULL DEFAULT '',
  loadout         JSONB,
  provider        TEXT,
  created_at      BIGINT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email   ON users(email)       WHERE email IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_handle  ON users(handle)      WHERE handle IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_invite  ON users(invite_code) WHERE invite_code IS NOT NULL;

-- ============================================================
-- 2. auth_identities
-- ============================================================
CREATE TABLE IF NOT EXISTS auth_identities (
  id                TEXT PRIMARY KEY,
  user_id           TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider          TEXT NOT NULL,
  provider_subject  TEXT,
  email             TEXT,
  password_hash     TEXT,
  email_verified    BOOLEAN NOT NULL DEFAULT false,
  created_at        BIGINT NOT NULL,
  updated_at        BIGINT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_provider_subject
  ON auth_identities(provider, provider_subject)
  WHERE provider_subject IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_auth_user    ON auth_identities(user_id);
CREATE INDEX IF NOT EXISTS idx_auth_email   ON auth_identities(email) WHERE email IS NOT NULL;

-- ============================================================
-- 3. oauth_index  (provider:subject → user_id)
-- ============================================================
CREATE TABLE IF NOT EXISTS oauth_index (
  oauth_key   TEXT PRIMARY KEY,   -- "google:<hash>" or "apple:<hash>"
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_oauth_user ON oauth_index(user_id);

-- ============================================================
-- 4. firebase_identity_index (legacy migration, can drop later)
-- ============================================================
CREATE TABLE IF NOT EXISTS firebase_identities (
  firebase_uid    TEXT PRIMARY KEY,
  app_user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email           TEXT,
  email_verified  BOOLEAN NOT NULL DEFAULT false,
  providers       JSONB,          -- ["google.com","apple.com",...]
  created_at      BIGINT NOT NULL,
  last_login_at   BIGINT NOT NULL
);

-- ============================================================
-- 5. email_verification_tokens
-- ============================================================
CREATE TABLE IF NOT EXISTS email_verification_tokens (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email       TEXT NOT NULL,
  token_hash  TEXT NOT NULL,
  expires_at  BIGINT NOT NULL,
  used_at     BIGINT,
  created_at  BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_evt_hash ON email_verification_tokens(token_hash);

-- ============================================================
-- 6. password_reset_tokens
-- ============================================================
CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email       TEXT NOT NULL,
  token_hash  TEXT NOT NULL,
  expires_at  BIGINT NOT NULL,
  used_at     BIGINT,
  created_at  BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_prt_hash ON password_reset_tokens(token_hash);

-- ============================================================
-- 7. refresh_tokens
-- ============================================================
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL,
  device_info TEXT,
  expires_at  BIGINT NOT NULL,
  revoked_at  BIGINT,
  created_at  BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rt_hash ON refresh_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_rt_user ON refresh_tokens(user_id) WHERE revoked_at IS NULL;

-- ============================================================
-- 8. friendships (bidirectional: insert 2 rows per friendship)
-- ============================================================
CREATE TABLE IF NOT EXISTS friendships (
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  friend_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  BIGINT NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW())::BIGINT),
  PRIMARY KEY (user_id, friend_id)
);

CREATE INDEX IF NOT EXISTS idx_friendships_friend ON friendships(friend_id);

-- ============================================================
-- 9. friend_requests
-- ============================================================
CREATE TABLE IF NOT EXISTS friend_requests (
  id            TEXT PRIMARY KEY,
  from_user_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  note          TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_freq_from ON friend_requests(from_user_id);
CREATE INDEX IF NOT EXISTS idx_freq_to   ON friend_requests(to_user_id);

-- ============================================================
-- 10. journeys (keep route data as JSONB, extract queryable fields)
-- ============================================================
CREATE TABLE IF NOT EXISTS journeys (
  id          TEXT NOT NULL,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title       TEXT,
  city_id     TEXT,
  distance    DOUBLE PRECISION DEFAULT 0,
  start_time  TIMESTAMPTZ,
  end_time    TIMESTAMPTZ,
  visibility  TEXT NOT NULL DEFAULT 'friendsOnly',
  data        JSONB NOT NULL,     -- full journey object
  created_at  BIGINT NOT NULL,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_journeys_user_time ON journeys(user_id, end_time DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_journeys_city      ON journeys(city_id) WHERE city_id IS NOT NULL;

-- ============================================================
-- 11. city_cards
-- ============================================================
CREATE TABLE IF NOT EXISTS city_cards (
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  city_id       TEXT NOT NULL,
  city_name     TEXT NOT NULL,
  country_iso2  TEXT,
  created_at    BIGINT NOT NULL,
  PRIMARY KEY (user_id, city_id)
);

-- ============================================================
-- 12. journey_likes
-- ============================================================
CREATE TABLE IF NOT EXISTS journey_likes (
  owner_user_id   TEXT NOT NULL,
  journey_id      TEXT NOT NULL,
  liker_user_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (owner_user_id, journey_id, liker_user_id)
);

CREATE INDEX IF NOT EXISTS idx_likes_journey ON journey_likes(owner_user_id, journey_id);
CREATE INDEX IF NOT EXISTS idx_likes_liker   ON journey_likes(liker_user_id);

-- ============================================================
-- 13. notifications
-- ============================================================
CREATE TABLE IF NOT EXISTS notifications (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type          TEXT NOT NULL,
  from_user_id  TEXT,
  from_display_name TEXT,
  journey_id    TEXT,
  journey_title TEXT,
  message       TEXT NOT NULL,
  read          BOOLEAN NOT NULL DEFAULT false,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notif_user ON notifications(user_id, created_at DESC);

-- ============================================================
-- 14. postcards
-- ============================================================
CREATE TABLE IF NOT EXISTS postcards (
  message_id        TEXT PRIMARY KEY,
  from_user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  from_display_name TEXT,
  to_user_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_display_name   TEXT,
  city_id           TEXT NOT NULL,
  city_name         TEXT NOT NULL,
  photo_url         TEXT,
  message_text      TEXT NOT NULL,
  client_draft_id   TEXT,
  status            TEXT NOT NULL DEFAULT 'sent',
  sent_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pc_to   ON postcards(to_user_id, sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_pc_from ON postcards(from_user_id, sent_at DESC);

-- ============================================================
-- 15. postcard_reactions
-- ============================================================
CREATE TABLE IF NOT EXISTS postcard_reactions (
  id                    TEXT PRIMARY KEY,
  postcard_message_id   TEXT NOT NULL REFERENCES postcards(message_id) ON DELETE CASCADE,
  from_user_id          TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  viewed_at             TIMESTAMPTZ,
  reaction_emoji        TEXT,
  comment               TEXT,
  reacted_at            TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_pcr_postcard_user
  ON postcard_reactions(postcard_message_id, from_user_id);

-- ============================================================
-- 16. push_tokens (APNs device tokens)
-- ============================================================
CREATE TABLE IF NOT EXISTS push_tokens (
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token       TEXT NOT NULL,
  platform    TEXT NOT NULL DEFAULT 'ios',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, token)
);

CREATE INDEX IF NOT EXISTS idx_push_tokens_user ON push_tokens(user_id);

COMMIT;
