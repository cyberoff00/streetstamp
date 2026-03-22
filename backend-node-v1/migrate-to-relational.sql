-- StreetStamps 关系型数据库迁移
-- 执行前备份: pg_dump > backup.sql

-- 用户表
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT,
  display_name TEXT NOT NULL,
  handle TEXT,
  invite_code TEXT,
  profile_visibility TEXT DEFAULT 'friendsOnly',
  profile_setup_completed BOOLEAN DEFAULT true,
  handle_change_used BOOLEAN DEFAULT false,
  bio TEXT DEFAULT '',
  loadout JSONB,
  created_at BIGINT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_handle ON users(handle) WHERE handle IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_invite ON users(invite_code) WHERE invite_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL;

-- 认证身份表
CREATE TABLE IF NOT EXISTS auth_identities (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  provider_subject TEXT,
  email TEXT,
  password_hash TEXT,
  email_verified BOOLEAN DEFAULT false,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_provider_subject
  ON auth_identities(provider, provider_subject)
  WHERE provider_subject IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_auth_email ON auth_identities(email) WHERE email IS NOT NULL;

-- 好友关系表
CREATE TABLE IF NOT EXISTS friendships (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  friend_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at BIGINT NOT NULL,
  PRIMARY KEY (user_id, friend_id)
);

CREATE INDEX IF NOT EXISTS idx_friendships_friend ON friendships(friend_id);

-- Journey表（保留JSONB，但独立存储）
CREATE TABLE IF NOT EXISTS journeys (
  id TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT,
  city_id TEXT,
  distance DOUBLE PRECISION DEFAULT 0,
  start_time TIMESTAMPTZ,
  end_time TIMESTAMPTZ,
  visibility TEXT DEFAULT 'friendsOnly',
  data JSONB NOT NULL,
  created_at BIGINT NOT NULL,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_journeys_user_time ON journeys(user_id, end_time DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_journeys_city ON journeys(city_id) WHERE city_id IS NOT NULL;

-- 城市卡片表
CREATE TABLE IF NOT EXISTS city_cards (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  city_id TEXT NOT NULL,
  city_name TEXT NOT NULL,
  country_iso2 TEXT,
  created_at BIGINT NOT NULL,
  PRIMARY KEY (user_id, city_id)
);

-- 点赞表
CREATE TABLE IF NOT EXISTS journey_likes (
  owner_user_id TEXT NOT NULL,
  journey_id TEXT NOT NULL,
  liker_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at BIGINT NOT NULL,
  PRIMARY KEY (owner_user_id, journey_id, liker_user_id)
);

CREATE INDEX IF NOT EXISTS idx_likes_journey ON journey_likes(owner_user_id, journey_id);
CREATE INDEX IF NOT EXISTS idx_likes_liker ON journey_likes(liker_user_id);

-- 好友请求表
CREATE TABLE IF NOT EXISTS friend_requests (
  id TEXT PRIMARY KEY,
  from_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_freq_from ON friend_requests(from_user_id);
CREATE INDEX IF NOT EXISTS idx_freq_to ON friend_requests(to_user_id);

-- 通知表
CREATE TABLE IF NOT EXISTS notifications (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  from_user_id TEXT,
  journey_id TEXT,
  message TEXT NOT NULL,
  read BOOLEAN DEFAULT false,
  data JSONB,
  created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_notif_user_unread ON notifications(user_id, read, created_at DESC);

-- 明信片表
CREATE TABLE IF NOT EXISTS postcards (
  id TEXT PRIMARY KEY,
  from_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  city_id TEXT NOT NULL,
  city_name TEXT NOT NULL,
  message_text TEXT NOT NULL,
  photo_url TEXT NOT NULL,
  read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_postcard_to ON postcards(to_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_postcard_from ON postcards(from_user_id, created_at DESC);

-- Refresh token表
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL,
  device_info TEXT,
  expires_at BIGINT NOT NULL,
  revoked_at BIGINT,
  created_at BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_refresh_token_hash ON refresh_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_refresh_user ON refresh_tokens(user_id) WHERE revoked_at IS NULL;
