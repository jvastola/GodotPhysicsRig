# Local Validation Log (2026-02-23)

Workspace: `/Users/jv/Documents/GodotPhysicsRig`
Runtime: Colima (`containerd` + `nerdctl compose`)

## 1. Bring up local runtime

```bash
colima start --runtime containerd
colima status
colima nerdctl version
colima nerdctl compose version
```

## 2. Start LiveKit (local)

```bash
cd /Users/jv/Documents/GodotPhysicsRig/multiplayer/servers/livekit-server
colima nerdctl -- compose up -d
```

### Fixes applied for local compose compatibility
- `livekit-server/docker-compose.yml`
  - Removed invalid `LIVEKIT_KEYS` env override (it conflicted with parser requirements).
  - Kept `config.yaml` mounted as source of keys.

## 3. Start Nakama (local)

```bash
cd /Users/jv/Documents/GodotPhysicsRig/multiplayer/servers/nakama
colima nerdctl -- compose up -d
```

### Local alignment applied
- `nakama/docker-compose.yml`
  - `LIVEKIT_API_KEY=devkey`
  - `LIVEKIT_API_SECRET=secret`
  - `LIVEKIT_WS_URL=ws://127.0.0.1:7880`

## 4. Verify module load and RPC registration

```bash
colima nerdctl -- logs nakama --tail 200
```

Expected log line observed:
- `Registered Lua runtime RPC function invocation` with id `livekit_token`.

## 5. RPC invocation tests

### Failing shape (object body)
```bash
curl -X POST http://127.0.0.1:7350/v2/rpc/livekit_token \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <nakama-token>' \
  -d '{"room":"x"}'
```
Result: `json: cannot unmarshal object into Go value of type string`

### Working shape (JSON string body)
```bash
curl -X POST http://127.0.0.1:7350/v2/rpc/livekit_token \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <nakama-token>' \
  -d '"{\"room\":\"body-room\",\"participant_id\":\"peer-local-1\",\"display_name\":\"Local Tester\"}"'
```
Result: success response containing `payload` with `token` and `ws_url`.

## 6. Code changes made during local validation

- `/Users/jv/Documents/GodotPhysicsRig/multiplayer/client/scripts/nakama_manager.gd`
  - `request_livekit_token(...)` now sends RPC body as a JSON string (`JSON.stringify(payload_json)`), matching Nakama Lua RPC expectations.

- `/Users/jv/Documents/GodotPhysicsRig/multiplayer/servers/nakama/data/modules/livekit_rpc.lua`
  - Uses canonical `require("nakama")` + `nk.register_rpc(...)`.
  - Local constants for key/secret currently used (`devkey`/`secret`) to avoid unavailable env getter APIs in this runtime.

- `/Users/jv/Documents/GodotPhysicsRig/multiplayer/servers/livekit-server/docker-compose.yml`
  - Removed invalid `LIVEKIT_KEYS` environment block.

## 7. Current local status

```bash
colima nerdctl -- ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```
- `livekit-server-livekit-1` up
- `nakama` up
- `postgres` up

