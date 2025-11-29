# Nakama Server - Oracle Cloud Firewall Configuration

## Current Status

✅ Nakama server is RUNNING on Oracle Cloud (158.101.21.99)
✅ Ubuntu firewall configured
⚠️ **ACTION REQUIRED**: Configure Oracle Cloud Security List

## Quick Setup Instructions

### Step 1: Configure Oracle Cloud Security List

You must add these firewall rules in Oracle Cloud Console to allow external access:

1. Go to [Oracle Cloud Console](https://cloud.oracle.com/)
2. Navigate to: **Compute** → **Instances** → Click your instance
3. Under **Instance Details**, click the **Subnet** link
4. Click **Default Security List**
5. Click **Add Ingress Rules**

Add these 3 rules (one at a time):

#### Rule 1: Nakama WebSocket API (Required for Game Clients)
- **Source Type**: CIDR
- **Source CIDR**: `0.0.0.0/0`
- **IP Protocol**: TCP
- **Destination Port Range**: `7350`
- **Description**: `Nakama WebSocket API`

#### Rule 2: Nakama Admin Console (Optional - for server management)
- **Source Type**: CIDR
- **Source CIDR**: `0.0.0.0/0`
- **IP Protocol**: TCP
- **Destination Port Range**: `7351`
- **Description**: `Nakama Admin Console`

#### Rule 3: Nakama gRPC (Optional - advanced use)
- **Source Type**: CIDR
- **Source CIDR**: `0.0.0.0/0`
- **IP Protocol**: TCP
- **Destination Port Range**: `7349`
- **Description**: `Nakama gRPC API`

### Step 2: Test Connection

After adding the rules, test from your local Windows machine:

```powershell
# Test Nakama API
curl http://158.101.21.99:7350/healthcheck

# Or test in browser
# Navigate to: http://158.101.21.99:7351
```

### Step 3: Configure Your Godot Client

Update your Godot project to connect to the Oracle Cloud server:

```gdscript
# In multiplayer/nakama_manager.gd or your initialization script
var nakama_host = "158.101.21.99"
var nakama_port = 7350
```

## Server Information

**Public IP**: 158.101.21.99

**Ports:**
- 7350 - Game client connections (WebSocket)
- 7351 - Admin console
- 7349 - gRPC API

**Admin Console:**
- URL: http://158.101.21.99:7351
- Username: `admin`
- Password: `password`

## Server Management

### SSH Connection
```bash
ssh -i "C:\Users\Admin\Downloads\privatessh-key-2025-11-20.key" ubuntu@158.101.21.99
```

### View Logs
```bash
cd ~/GodotPhysicsRig/nakama
docker logs nakama -f
```

### Restart Server
```bash
cd ~/GodotPhysicsRig/nakama
docker-compose restart
```

### Stop Server
```bash
docker-compose down
```

### Start Server
```bash
docker-compose up -d
```

## Troubleshooting

### Can't connect from outside
- ✅ Check Oracle Cloud Security List rules are added
- ✅ Verify containers are running: `docker ps`
- ✅ Check logs: `docker logs nakama`

### Server not responding
```bash
# SSH into server
cd ~/GodotPhysicsRig/nakama
docker-compose restart
docker logs nakama --tail 50
```
