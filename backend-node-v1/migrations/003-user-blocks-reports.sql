-- User blocks table
CREATE TABLE IF NOT EXISTS user_blocks (
  blocker_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at BIGINT NOT NULL,
  PRIMARY KEY (blocker_user_id, blocked_user_id)
);

CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON user_blocks(blocked_user_id);

-- User/content reports table
CREATE TABLE IF NOT EXISTS reports (
  id TEXT PRIMARY KEY,
  reporter_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reported_user_id TEXT NOT NULL,
  content_type TEXT NOT NULL,        -- 'user', 'journey', 'postcard'
  content_id TEXT,                    -- journey_id or postcard_id (NULL for user reports)
  reason TEXT NOT NULL,               -- 'spam', 'harassment', 'inappropriate', 'other'
  detail TEXT DEFAULT '',
  status TEXT DEFAULT 'pending',      -- 'pending', 'reviewed', 'actioned'
  created_at BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_reports_reporter ON reports(reporter_user_id);
CREATE INDEX IF NOT EXISTS idx_reports_reported ON reports(reported_user_id);
CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status) WHERE status = 'pending';
