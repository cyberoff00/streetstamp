# StreetStamps Backend (Go)

Go 标准库实现，适合先在 ECS 快速上线。

## Run

```bash
cd backend
go run .
```

## Build

```bash
go build -o streetstamps-backend .
```

## Env

- `PORT` default `8080`
- `JWT_SECRET` default `change-me-in-production`
- `DATA_FILE` default `./data.json`
- `MEDIA_DIR` default `./media`
- `MEDIA_PUBLIC_BASE` optional, e.g. `https://api.your-domain.com`
- `R2_ACCOUNT_ID` optional, set to enable R2 upload
- `R2_ACCESS_KEY_ID` optional
- `R2_SECRET_ACCESS_KEY` optional
- `R2_BUCKET` optional
- `R2_ENDPOINT` optional, default `https://<account-id>.r2.cloudflarestorage.com`
- `R2_PUBLIC_BASE` optional public URL base, e.g. `https://media.your-domain.com`
- `R2_REGION` optional, default `auto`

## Core endpoints

- `GET /v1/health`
- `POST /v1/auth/email/register`
- `POST /v1/auth/email/login`
- `POST /v1/auth/oauth`
- `GET /v1/friends` (Bearer)
- `POST /v1/friends` (Bearer)
- `DELETE /v1/friends/{friendID}` (Bearer)
- `POST /v1/journeys/migrate` (Bearer)
- `GET /v1/profile/me` (Bearer)
- `GET /v1/profile/{userID}` (Bearer)
- `POST /v1/media/upload` (Bearer, multipart)

## Deployment

参考：
- `backend/API.md`
- `backend/ARCHITECTURE.md`

Systemd and Nginx sample can reuse你之前的部署方式：
- `ExecStart=/opt/streetstamps/backend/streetstamps-backend`
- Nginx proxy to `127.0.0.1:8080`
