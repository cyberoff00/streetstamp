# API v1

## Health
- `GET /v1/health`

## Auth
- `POST /v1/auth/email/register`
- `POST /v1/auth/email/login`
- `POST /v1/auth/oauth`

Response shape:
```json
{
  "userId": "u_xxx",
  "provider": "email|apple|google",
  "email": "a@b.com",
  "accessToken": "...",
  "refreshToken": "..."
}
```

## Friends (Bearer)
- `GET /v1/friends`
- `POST /v1/friends`
- `DELETE /v1/friends/{friendID}`

`POST /v1/friends` body:
```json
{
  "displayName": "Alice or @alice_handle",
  "inviteCode": "A1B2C3D4"
}
```
Notes:
- `inviteCode` 优先匹配已有用户。
- 若 `displayName` 以 `@` 开头，会按 handle 匹配用户。
- 若两者都匹配不到，会创建一个 manual friend（用于演示/冷启动）。

## Cloud migration (Bearer)
- `POST /v1/journeys/migrate`

Body:
```json
{
  "journeys": [
    {
      "id": "j_1",
      "title": "City Walk",
      "activityTag": "步行",
      "overallMemory": "...",
      "distance": 6200,
      "startTime": "2026-02-19T12:00:00Z",
      "endTime": "2026-02-19T13:00:00Z",
      "visibility": "private|friendsOnly|public",
      "routeCoordinates": [
        { "lat": 31.2304, "lon": 121.4737 },
        { "lat": 31.2320, "lon": 121.4801 }
      ],
      "memories": [
        {
          "id": "m_1",
          "title": "...",
          "notes": "...",
          "timestamp": "2026-02-19T12:30:00Z",
          "imageURLs": ["https://..."]
        }
      ]
    }
  ],
  "unlockedCityCards": [
    { "id": "Shanghai|CN", "name": "Shanghai", "countryISO2": "CN" }
  ]
}
```

## Profile (Bearer)
- `GET /v1/profile/me`
- `GET /v1/profile/{userID}`

Profile response shape:
```json
{
  "id": "u_xxx",
  "handle": "@mora_ab12cd",
  "inviteCode": "A1B2C3D4",
  "profileVisibility": "private|friendsOnly|public",
  "displayName": "Explorer",
  "bio": "Travel Enthusiastic",
  "loadout": {},
  "stats": {
    "totalJourneys": 3,
    "totalDistance": 12800,
    "totalMemories": 9,
    "totalUnlockedCities": 4
  },
  "journeys": [
    {
      "id": "j_1",
      "title": "City Walk",
      "routeCoordinates": [
        { "lat": 31.2304, "lon": 121.4737 },
        { "lat": 31.2320, "lon": 121.4801 }
      ],
      "memories": []
    }
  ],
  "unlockedCityCards": []
}
```

## Media upload (Bearer)
- `POST /v1/media/upload` (`multipart/form-data`, field name: `file`)

Response:
```json
{
  "objectKey": "u_xxx/abcd1234.jpg",
  "url": "/media/u_xxx/abcd1234.jpg"
}
```

## Error format
```json
{ "message": "reason" }
```
