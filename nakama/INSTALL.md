# Nakama Local Setup - Installation Guide

## Prerequisites Check

You have:
- ✅ Docker CLI installed (`docker --version`)
- ✅ docker-compose installed (`docker-compose --version`)
- ❌ Docker daemon not running

## Option 1: Install Docker Desktop (Recommended)

### macOS Installation

1. **Download Docker Desktop:**
   - Visit: https://www.docker.com/products/docker-desktop/
   - Click "Download for Mac" (Apple Silicon or Intel)

2. **Install:**
   ```bash
   # Open the downloaded .dmg and drag Docker to Applications
   open ~/Downloads/Docker.dmg
   ```

3. **Start Docker:**
   - Open Docker Desktop from Applications
   - Wait for "Docker Desktop is running" notification
   - Check status: `docker ps`

4. **Start Nakama:**
   ```bash
   cd nakama
   docker-compose up -d
   ```

## Option 2: Use Colima (Lightweight Alternative)

If you don't want Docker Desktop, use Colima - a lightweight Docker runtime:

```bash
# Install Colima
brew install colima

# Start Colima
colima start

# Verify Docker works
docker ps

# Start Nakama
cd nakama
docker-compose up -d
```

**Colima is lighter and faster than Docker Desktop!**

## Option 3: Skip Local Setup (Use Cloud)

If you want to skip local testing, you can:

1. Deploy Nakama directly to Oracle Cloud (same setup as your matchmaking server)
2. Use Nakama Cloud (hosted): https://heroiclabs.com/nakama-cloud/
3. Test with your Oracle Cloud instance

## Verification

After starting Docker, verify Nakama is running:

```bash
# Check containers
docker ps

# Should see:
# nakama       (port 7350, 7351)
# postgres     (port 5432)

# Test connection
curl http://localhost:7350

# Open admin console
open http://localhost:7351
```

## Current Status

Your system needs one of these:
- [ ] Docker Desktop installed and running
- [ ] Colima installed and running
- [ ] Deploy to cloud instead

**Recommendation:** Install Colima (faster, lighter) or Docker Desktop (official)

## Next Steps

Once Docker is running:
1. `cd nakama && docker-compose up -d`
2. Wait ~30 seconds for Nakama to start
3. Test: `curl http://localhost:7350`
4. Open admin: http://localhost:7351 (admin/password)
