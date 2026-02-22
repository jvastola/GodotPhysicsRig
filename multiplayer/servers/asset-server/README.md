# Asset Server

Backend server for hosting player-published scenes, avatars, and GLTF models.

## Quick Start

### 1. Start Database (if not already running)
```bash
cd ../nakama
docker-compose up -d postgres
```

### 2. Install Dependencies
```bash
npm install
```

### 3. Run Migrations
```bash
npm run migrate
```

### 4. Start Server
```bash
npm start
```

Server runs at **http://localhost:3001**

## API Endpoints

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | /assets | - | Browse/search assets |
| GET | /assets/:id | - | Get asset details |
| GET | /assets/:id/download | - | Download asset file |
| POST | /assets | ✓ | Upload new asset |
| PUT | /assets/:id | ✓ | Update asset |
| DELETE | /assets/:id | ✓ | Delete asset |
| POST | /assets/:id/like | ✓ | Like/unlike asset |
| GET | /categories | - | List categories |

## Query Parameters (GET /assets)

| Param | Values | Default |
|-------|--------|---------|
| category | scene, avatar, model | - |
| search | text | - |
| tags | comma-separated | - |
| sort | downloads, likes, created_at | created_at |
| order | asc, desc | desc |
| page | number | 1 |
| limit | 1-50 | 20 |

## Environment Variables

```bash
PORT=3001
DATABASE_URL=postgres://postgres:localdb@localhost:5432/nakama
NAKAMA_URL=http://localhost:7350
STORAGE_PROVIDER=local
UPLOAD_DIR=./uploads
```

## Docker Deployment

```bash
# Build and run with existing Nakama stack
docker-compose up -d
```
