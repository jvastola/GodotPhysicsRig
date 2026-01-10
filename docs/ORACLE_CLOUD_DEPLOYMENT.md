# Oracle Cloud Deployment Guide

Complete guide for deploying **Nakama** and **Asset Server** on Oracle Cloud.

---

## Server Info

| Item | Value |
|------|-------|
| **Public IP** | 158.101.21.99 |
| **SSH Key** | `C:\Users\Admin\Downloads\privatessh-key-2025-11-20.key` |

| Service | Port | URL |
|---------|------|-----|
| Nakama API | 7350 | http://158.101.21.99:7350 |
| Nakama Admin | 7351 | http://158.101.21.99:7351 |
| Asset Server | 3001 | http://158.101.21.99:3001 |

---

## Part 1: Oracle Cloud Firewall Setup

### Add Security Rules

1. Go to [Oracle Cloud Console](https://cloud.oracle.com/)
2. **Compute** → **Instances** → Click instance
3. Click **Subnet** → **Default Security List** → **Add Ingress Rules**

| Port | Protocol | Source CIDR | Description |
|------|----------|-------------|-------------|
| 7350 | TCP | 0.0.0.0/0 | Nakama WebSocket API |
| 7351 | TCP | 0.0.0.0/0 | Nakama Admin Console |
| 3001 | TCP | 0.0.0.0/0 | Asset Library Server |

---

## Part 2: SSH to Server

```bash
ssh -i "C:\Users\Admin\Downloads\privatessh-key-2025-11-20.key" ubuntu@158.101.21.99
```

---

## Part 3: Deploy Nakama

```bash
cd ~/GodotPhysicsRig/nakama
docker-compose up -d
```

Verify:
```bash
curl http://localhost:7350/healthcheck
```

---

## Part 4: Deploy Asset Server

### Install Node.js (if needed)
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
```

### Deploy
```bash
cd ~/GodotPhysicsRig/asset-server
npm install
npm run migrate
npm start
```

### Run as Background Service
```bash
# Using PM2 (recommended)
sudo npm install -g pm2
pm2 start server.js --name asset-server
pm2 save
pm2 startup

# Or using nohup
nohup node server.js > server.log 2>&1 &
```

### Docker Deployment (Alternative)
```bash
cd ~/GodotPhysicsRig/asset-server
docker build -t asset-server .
docker run -d --name asset-server \
  -p 3001:3001 \
  --network nakama_default \
  -e DATABASE_URL=postgres://postgres:localdb@postgres:5432/nakama \
  -e NAKAMA_URL=http://nakama:7350 \
  -v $(pwd)/uploads:/app/uploads \
  asset-server
```

---

## Part 5: Ubuntu Firewall

```bash
sudo ufw allow 7350/tcp
sudo ufw allow 7351/tcp
sudo ufw allow 3001/tcp
sudo ufw reload
```

---

## Part 6: Godot Client Configuration

Update your client to use the cloud server:

```gdscript
# multiplayer/nakama_manager.gd
var nakama_host = "158.101.21.99"
var nakama_port = 7350

# src/ui/asset_library_ui.gd
const ASSET_SERVER_URL = "http://158.101.21.99:3001"
```

---

## Quick Commands

| Action | Command |
|--------|---------|
| SSH | `ssh -i "...\privatessh-key-2025-11-20.key" ubuntu@158.101.21.99` |
| Nakama logs | `docker logs nakama -f` |
| Restart Nakama | `cd ~/GodotPhysicsRig/nakama && docker-compose restart` |
| Asset Server logs | `pm2 logs asset-server` |
| Restart Asset Server | `pm2 restart asset-server` |

---

## Test Endpoints

```bash
# Nakama health
curl http://158.101.21.99:7350/healthcheck

# Asset Server health
curl http://158.101.21.99:3001/health

# Browse assets
curl http://158.101.21.99:3001/assets
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Connection refused | Check Oracle Security List rules |
| Database error | Ensure Nakama/PostgreSQL is running |
| Asset upload fails | Check disk space and permissions |
