# Oracle Cloud Command Log (2026-02-23)

This log captures escalated commands executed from local workstation to Oracle host `ubuntu@158.101.21.99`.

## 1. SSH Access Prep

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key -o StrictHostKeyChecking=accept-new ubuntu@158.101.21.99 'hostname && pwd'
```
- Result: failed due key mode `0644` (OpenSSH rejected key).

```bash
chmod 600 /Users/jv/Documents/privatessh-key-2025-11-20.key
```
- Result: success.

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key -o StrictHostKeyChecking=accept-new ubuntu@158.101.21.99 'hostname && pwd'
```
- Result: success (`godot-vnic`, `/home/ubuntu`).

## 2. Service Discovery / Inspection

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key ubuntu@158.101.21.99 'docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" && echo "---" && ls -la /home/ubuntu && echo "---" && ls -la /home/ubuntu/GodotPhysicsRig || true'
```
- Result: identified running containers:
  - `livekit_server_livekit_1`
  - `livekit_server_redis_1`
  - `nakama`
  - `postgres`
  - `godot-matchmaking`

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key ubuntu@158.101.21.99 'set -e; echo "== livekit_server =="; ls -la /home/ubuntu/GodotPhysicsRig/livekit_server; echo "== nakama =="; ls -la /home/ubuntu/GodotPhysicsRig/nakama; echo "== multiplayer =="; ls -la /home/ubuntu/GodotPhysicsRig/multiplayer'
```
- Result: service directories confirmed.

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key ubuntu@158.101.21.99 'echo "== /home/ubuntu/GodotPhysicsRig/livekit_server/docker-compose.yml =="; cat /home/ubuntu/GodotPhysicsRig/livekit_server/docker-compose.yml; echo; echo "== /home/ubuntu/GodotPhysicsRig/livekit_server/livekit.yaml =="; cat /home/ubuntu/GodotPhysicsRig/livekit_server/livekit.yaml; echo; echo "== /home/ubuntu/GodotPhysicsRig/nakama/docker-compose.yml =="; cat /home/ubuntu/GodotPhysicsRig/nakama/docker-compose.yml; echo; echo "== /home/ubuntu/GodotPhysicsRig/nakama/data/local.yml =="; cat /home/ubuntu/GodotPhysicsRig/nakama/data/local.yml'
```
- Result:
  - LiveKit host-mode config, `ws://<ip>:7880` style transport
  - LiveKit key/secret present in `livekit.yaml`
  - Nakama 3.21.1 stack active

## 3. Matchmaking Container Inspection

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key ubuntu@158.101.21.99 'docker inspect godot-matchmaking --format "Image={{.Config.Image}} Cmd={{json .Config.Cmd}} Env={{json .Config.Env}}"; echo "---"; curl -sS http://127.0.0.1:8080/health || true; echo; echo "---"; curl -sS http://127.0.0.1:8080/ | head -c 400 || true; echo'
```
- Result: service healthy, room endpoints present, no LiveKit token endpoint exposed.

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key ubuntu@158.101.21.99 'docker exec godot-matchmaking sh -lc "ls -la /app && grep -n \"app\.\|token\|livekit\|/rooms\|/health\" /app/server.js | head -n 200"'
```
- Result: endpoint list confirms `/health`, `/room`, `/rooms`; no `/livekit/token`.

## 4. Nakama Runtime RPC Attempt (Rolled Back)

### 4.1 Backup

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key ubuntu@158.101.21.99 'set -e; TS=$(date +%Y%m%d-%H%M%S); BACKUP=/home/ubuntu/GodotPhysicsRig/.deploy_backup_$TS; mkdir -p "$BACKUP"; cp /home/ubuntu/GodotPhysicsRig/nakama/docker-compose.yml "$BACKUP"/nakama-docker-compose.yml; cp /home/ubuntu/GodotPhysicsRig/nakama/data/local.yml "$BACKUP"/nakama-local.yml; echo "$BACKUP"'
```
- Result: backup created: `/home/ubuntu/GodotPhysicsRig/.deploy_backup_20260223-044839`.

### 4.2 Deploy Attempt

```bash
scp -i /Users/jv/Documents/privatessh-key-2025-11-20.key multiplayer/servers/nakama/docker-compose.yml multiplayer/servers/nakama/data/local.yml multiplayer/servers/nakama/data/modules/livekit_rpc.lua ubuntu@158.101.21.99:/home/ubuntu/GodotPhysicsRig/nakama/.
```
- Result: files uploaded.

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key ubuntu@158.101.21.99 'set -e; mkdir -p /home/ubuntu/GodotPhysicsRig/nakama/data/modules; mv /home/ubuntu/GodotPhysicsRig/nakama/local.yml /home/ubuntu/GodotPhysicsRig/nakama/data/local.yml; mv /home/ubuntu/GodotPhysicsRig/nakama/livekit_rpc.lua /home/ubuntu/GodotPhysicsRig/nakama/data/modules/livekit_rpc.lua; ls -la /home/ubuntu/GodotPhysicsRig/nakama/data/modules'
```
- Result: initial module move failed due permissions in root-owned `modules/`.

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key ubuntu@158.101.21.99 'set -e; sudo mv /home/ubuntu/GodotPhysicsRig/nakama/livekit_rpc.lua /home/ubuntu/GodotPhysicsRig/nakama/data/modules/livekit_rpc.lua; sudo chown ubuntu:ubuntu /home/ubuntu/GodotPhysicsRig/nakama/data/modules/livekit_rpc.lua; ls -la /home/ubuntu/GodotPhysicsRig/nakama/data/modules'
```
- Result: success.

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key ubuntu@158.101.21.99 'set -e; cd /home/ubuntu/GodotPhysicsRig/nakama; docker-compose up -d; docker ps --filter name=nakama --format "table {{.Names}}\t{{.Status}}"; docker logs nakama --tail 120'
```
- Result: service started with module loaded, but runtime RPC registration was not successful.

### 4.3 RPC Validation

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key ubuntu@158.101.21.99 'set -e; AUTH=$(curl -sS -X POST "http://127.0.0.1:7350/v2/account/authenticate/device?create=true" -H "Content-Type: application/json" -H "Authorization: Basic ZGVmYXVsdGtleTo=" -d "{\"id\":\"oracle-rpc-smoke-test\"}"); TOKEN=$(echo "$AUTH" | sed -n "s/.*\"token\":\"\([^\"]*\)\".*/\1/p"); test -n "$TOKEN"; echo "Auth OK"; RPC=$(curl -sS -X POST "http://127.0.0.1:7350/v2/rpc/livekit_token" -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d "{\"room\":\"rpc-test-room\"}"); echo "$RPC"'
```
- Result: `{"error":"RPC function not found"...}`.

Subsequent registration variants caused Nakama Lua init failure and restart loop.

## 5. Rollback and Recovery

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key ubuntu@158.101.21.99 'set -e; BACKUP=/home/ubuntu/GodotPhysicsRig/.deploy_backup_20260223-044839; cp "$BACKUP"/nakama-docker-compose.yml /home/ubuntu/GodotPhysicsRig/nakama/docker-compose.yml; cp "$BACKUP"/nakama-local.yml /home/ubuntu/GodotPhysicsRig/nakama/data/local.yml; sudo rm -f /home/ubuntu/GodotPhysicsRig/nakama/data/modules/livekit_rpc.lua; cd /home/ubuntu/GodotPhysicsRig/nakama; docker-compose up -d; sleep 3; docker ps --filter name=nakama --format "table {{.Names}}\t{{.Status}}"; docker logs nakama --tail 80'
```
- Result: rollback completed; Nakama restored and healthy.

## Final Remote State

- Nakama restored to pre-change configs from backup.
- `livekit_rpc.lua` removed from Oracle runtime modules.
- Nakama container healthy and serving ports `7349/7350/7351`.
- LiveKit stack unchanged.
- No persistent service outage after rollback.

---

## 6. Local-Validated Oracle Redeploy (Successful)

After validating locally with Colima, deployment retried on Oracle using:
- top-level `require("nakama")`
- top-level `nk.register_rpc(...)`
- client request body as JSON string

### 6.1 Backup

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key ubuntu@158.101.21.99 'set -e; TS=$(date +%Y%m%d-%H%M%S); B=/home/ubuntu/GodotPhysicsRig/.deploy_backup_$TS; mkdir -p "$B"; cp /home/ubuntu/GodotPhysicsRig/nakama/docker-compose.yml "$B"/nakama-docker-compose.yml; cp /home/ubuntu/GodotPhysicsRig/nakama/data/local.yml "$B"/nakama-local.yml; if [ -f /home/ubuntu/GodotPhysicsRig/nakama/data/modules/livekit_rpc.lua ]; then sudo cp /home/ubuntu/GodotPhysicsRig/nakama/data/modules/livekit_rpc.lua "$B"/livekit_rpc.lua.bak; fi; echo "$B"'
```
- Backup path: `/home/ubuntu/GodotPhysicsRig/.deploy_backup_20260223-052046`

### 6.2 Module install

```bash
scp -i /Users/jv/Documents/privatessh-key-2025-11-20.key /tmp/livekit_rpc_oracle.lua ubuntu@158.101.21.99:/home/ubuntu/GodotPhysicsRig/nakama/livekit_rpc.lua
```

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key ubuntu@158.101.21.99 'set -e; sudo mkdir -p /home/ubuntu/GodotPhysicsRig/nakama/data/modules; sudo cp /home/ubuntu/GodotPhysicsRig/nakama/livekit_rpc.lua /home/ubuntu/GodotPhysicsRig/nakama/data/modules/livekit_rpc.lua; sudo chown root:root /home/ubuntu/GodotPhysicsRig/nakama/data/modules/livekit_rpc.lua; sudo chmod 644 /home/ubuntu/GodotPhysicsRig/nakama/data/modules/livekit_rpc.lua'
```

### 6.3 Restart + log validation

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key ubuntu@158.101.21.99 'cd /home/ubuntu/GodotPhysicsRig/nakama && docker-compose restart nakama'
```

Validated log line:
- `Registered Lua runtime RPC function invocation` with id `livekit_token`

### 6.4 Final RPC smoke test (success)

```bash
ssh -i /Users/jv/Documents/privatessh-key-2025-11-20.key ubuntu@158.101.21.99 'set -e; AUTH=$(curl -sS -X POST "http://127.0.0.1:7350/v2/account/authenticate/device?create=true" -H "Content-Type: application/json" -H "Authorization: Basic ZGVmYXVsdGtleTo=" -d "{\"id\":\"oracle-rpc-smoke-final2\"}"); TOKEN=$(echo "$AUTH" | sed -n "s/.*\"token\":\"\\([^\"]*\\)\".*/\\1/p"); BODY=$(python3 - <<\"PY\"\n+import json\n+payload={\"room\":\"oracle-room-test\",\"participant_id\":\"oracle-peer-1\",\"display_name\":\"Oracle Tester\"}\n+print(json.dumps(json.dumps(payload)))\n+PY\n+); curl -sS -X POST "http://127.0.0.1:7350/v2/rpc/livekit_token" -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" --data "$BODY"'
```

Response included:
- `payload.token` (valid JWT string)
- `payload.ws_url = ws://158.101.21.99:7880`
- `payload.room = oracle-room-test`

## Current State
- Oracle Nakama: healthy
- Oracle LiveKit: unchanged and running
- `livekit_token` RPC: active and validated
