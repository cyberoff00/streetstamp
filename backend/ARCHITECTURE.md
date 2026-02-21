# Storage Architecture (Production-Oriented)

## 1. Data split

- **Metadata in DB**
  - users, friendships
  - journeys (title, distance, visibility, timestamps)
  - memories (text, timestamp)
  - media references (object key / URL)
- **Binary in Object Storage**
  - images/videos from journey memories
  - recommended: Cloudflare R2 (or Alibaba OSS)

Current code keeps metadata in `data.json` for quick deployment. This can be swapped to Postgres without changing API contracts.

## 2. Route storage

Recommended final shape:
- `journey_route_summary`: encoded polyline (fast read)
- `journey_route_points`: optional raw points (debug/replay)

Current migration endpoint stores journey-level summary fields used by app and social views.

## 3. Visibility policy

Visibility values:
- `private`
- `friendsOnly`
- `public`

Server enforces filtering in:
- `GET /v1/profile/{id}`
- `GET /v1/friends`

## 4. Migration policy

1. User logs in.
2. App uploads media via `POST /v1/media/upload`.
3. App posts merged snapshot via `POST /v1/journeys/migrate`.
4. Server overwrites user's cloud snapshot atomically.

Supports retry: app can rerun migration safely.

## 5. When to provide R2 keys

Provide keys only when deploying backend (never in iOS app):
- `R2_ACCOUNT_ID`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_BUCKET`

In current implementation media is stored on local disk (`MEDIA_DIR`).
You can switch storage backend to R2 later while keeping the same API.
