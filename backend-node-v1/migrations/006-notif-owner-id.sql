-- Adds `owner_id` to notifications so journey_comment notifications can carry
-- the journey owner's user ID. The in-app inbox uses this to deep-link the
-- tap into the right viewer/owner mode of the comment sheet. Other
-- notification types leave this column null.
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS owner_id TEXT;
