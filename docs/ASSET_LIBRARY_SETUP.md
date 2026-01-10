# Asset Library Setup Guide

Complete setup for **Nakama** (multiplayer/auth) + **Asset Server** (content library) + **Godot client**.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) running
- [Node.js 18+](https://nodejs.org/)
- Godot 4.x

---

## 1. Start Nakama

```bash
cd nakama
docker-compose up -d
```

| Service | URL |
|---------|-----|
| Game API | http://localhost:7350 |
| Admin Console | http://localhost:7351 (admin/password) |

---

## 2. Start Asset Server

```bash
cd asset-server
npm install
npm run migrate
npm start
```

Server runs at **http://localhost:3001**

---

## 3. Godot Integration

Update `asset_library_ui.gd`:

```gdscript
const ASSET_SERVER_URL = "http://localhost:3001"
# For Quest: use your machine IP instead of localhost
```

### Browse Assets
```gdscript
http_request.request(ASSET_SERVER_URL + "/assets?category=model")
```

### Download Asset
```gdscript
http_request.request(ASSET_SERVER_URL + "/assets/" + id + "/download")
```

### Upload (Requires Auth)
Include Nakama token in header:
```gdscript
var headers = ["Authorization: Bearer " + NakamaManager.session.token]
```

---

## API Reference

| Action | Endpoint |
|--------|----------|
| Browse | `GET /assets?category=model` |
| Download | `GET /assets/{id}/download` |
| Upload | `POST /assets` |
| Like | `POST /assets/{id}/like` |

### Query Params
- `category`: scene, avatar, model
- `search`: text search
- `sort`: downloads, likes, created_at
- `page`, `limit`: pagination

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| DB error | Start Nakama first |
| Quest can't connect | Use machine IP, same WiFi |
| Auth fails | Check Nakama session token |
