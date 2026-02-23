# Networking Implementation Plan (Nakama + LiveKit + Asset Server)

## Scope
- Target: 20 players per room
- Authority model: Host authoritative (oldest Nakama presence)
- Persistence:
  - Placed objects persist while room exists
  - Optional user-triggered room save persists across room restart
- Transport:
  - Nakama = control/authority plane
  - LiveKit DataChannel = realtime replication plane
- Asset server = room save/load persistence plane

## Execution Status (2026-02-23)
- Completed:
  - Client no longer signs LiveKit tokens in UI/gameplay scripts.
  - Client now requests `livekit_token` from Nakama (`NakamaManager.request_livekit_token`).
  - Nakama RPC request body shape fixed for Lua runtime (`JSON string`, not object).
  - Oracle Nakama updated with `livekit_token` Lua module and validated by smoke test.
  - Oracle smoke test (success): `/v2/rpc/livekit_token` returned JWT + `ws_url`.
- In progress:
  - Move Oracle Lua module from host data path to tracked + automated deploy path.
  - Asset server room save APIs.
  - LiveKit wrapper/datachannel work.
- Completed:
  - Replaced hardcoded key/secret in Lua with env-driven runtime config (`LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_WS_URL`).
  - Phase 2 scaffolding in client:
    - ownership request/grant/deny/release opcodes and handlers
    - host-side object registry (`room_object_registry`)
    - oldest-presence host tracking + stable network ID helper
    - snapshot request/chunk/done handshake with chunked reconstruction
    - disconnect cleanup rules for `transient_held` vs placed objects

## Critical Findings To Fix First
1. LiveKit API keys/secrets are embedded in client scripts.
2. `match_handler.lua` opcode map does not match `multiplayer/client/scripts/nakama_manager.gd`.
3. Ownership and grab locks are still partly client-trusted.
4. LiveKit wrapper currently stringifies inbound data and drops channel/topic.

---

## Phase 1 - Security + Protocol Baseline (Easy Wins)

### 1.1 Remove client-side token signing
- Remove token minting logic from:
  - `src/ui/multiplayer/UnifiedRoomUI.gd`
  - `src/player/components/player_movement_component.gd`
  - `src/ui/livekit/livekit_utils.gd` (or convert to non-secret utility only)
- Replace with Nakama RPC:
  - `rpc_livekit_token(room_name)` returns signed JWT.

### 1.2 Add Nakama runtime RPC for LiveKit token
- Update:
  - `multiplayer/servers/nakama/data/modules/main.lua`
- Add:
  - `initializer.register_rpc(rpc_livekit_token, "livekit_token")`
- Add env-driven secrets in Nakama container:
  - `LIVEKIT_API_KEY`
  - `LIVEKIT_API_SECRET`
  - `LIVEKIT_URL`

### 1.3 Fix opcode consistency
- Canonicalize opcodes in one shared table and sync:
  - `multiplayer/client/scripts/nakama_manager.gd`
  - `multiplayer/servers/nakama/data/modules/match_handler.lua`
- Acceptance: same numeric values on both sides.

### 1.4 Harden host election
- Replace lexicographic ID authority with oldest presence by join order.
- File:
  - `multiplayer/client/scripts/network_manager.gd`

---

## Phase 2 - Authority + Ownership Protocol

### 2.1 Add control message types (Nakama reliable)
- `OWNERSHIP_REQUEST`
- `OWNERSHIP_GRANTED`
- `OWNERSHIP_DENIED`
- `OWNERSHIP_RELEASED`
- `SNAPSHOT_REQUEST`
- `SNAPSHOT_CHUNK`
- `SNAPSHOT_DONE`

### 2.2 Host-side object registry
- Add in `network_manager.gd`:
  - `room_object_registry: object_id -> state`
  - state fields:
    - `owner_id`, `held_by`, `placed`, `persist_mode`, `manifest_id`, `seq`

### 2.3 Enforce authority checks
- Only host can grant ownership.
- Non-owner transform/property updates ignored.
- On disconnect:
  - `transient_held` => despawn
  - `placed_room` => keep, clear `held_by`, owner -> host
  - `placed_saved` => keep and include in save blob

---

## Phase 3 - LiveKit DataChannel Replication

### 3.1 Wrapper updates
- File: `src/livekit_wrapper.gd`
- Add:
  - binary-safe send/receive APIs
  - topic/channel passthrough
  - explicit reliable/unreliable send methods

### 3.2 Android plugin updates
- File:
  - `multiplayer/plugins/livekit-android/src/main/kotlin/com/jvastola/physicshand/livekit/GodotLiveKitPlugin.kt`
- Add methods:
  - `sendDataReliable`, `sendDataUnreliable`
  - `sendDataToReliable`, `sendDataToUnreliable`
- Emit data_received with topic preserved.

### 3.3 Rust GDExtension updates
- File:
  - `multiplayer/plugins/godot-livekit/rust/src/livekit_client.rs`
- Add GDExtension funcs:
  - `send_reliable_data(data: GString)`
  - `send_unreliable_data(data: GString)`
  - `send_data_to(data: GString, identity: GString, reliable: bool)`
- Emit `data_received(identity, payload, topic)` equivalent via wrapper contract.

---

## Phase 4 - Property Manifest + Rates

### 4.1 Replication manifest model
- Add manifest per replicated node:
  - `high_rate_unreliable` (e.g. transform)
  - `reliable_on_change` (e.g. material, collision, mesh toggles)
  - `snapshot_only`

### 4.2 Rate tiers (20-player target)
- Player head/hands: 15 Hz unreliable
- Held object transform: 20 Hz unreliable
- Idle/far objects: 2-5 Hz or event-only
- Enforce seq numbers and stale packet drops.

---

## Phase 5 - Late Join Snapshot

### 5.1 Snapshot handshake
- Joiner sends `SNAPSHOT_REQUEST` to host.
- Host streams `SNAPSHOT_CHUNK` reliable, then `SNAPSHOT_DONE`.
- Joiner applies snapshot baseline then live deltas.

### 5.2 Chunking constraints
- Keep chunk payload bounded for mobile safety.
- Retry timed-out chunk IDs.

---

## Phase 6 - Save/Load Across Room Restart

### 6.1 Asset server room endpoints
- Add endpoints:
  - `POST /rooms/:room_id/save`
  - `GET /rooms/:room_id/state`
- Files:
  - `multiplayer/servers/asset-server/server.js`
  - `multiplayer/servers/asset-server/migrate.js` (new table)

### 6.2 Persisted payload
- Save only `placed_saved` object graph + manifests + durable properties.
- Exclude transient held state.

---

## Oracle Deployment Runbook

## Services to update
- Nakama container stack (runtime modules + env)
- LiveKit server (env/key rotation if needed)
- Asset server container stack

## Deployment sequence
1. Deploy Nakama runtime module updates. ✅
2. Set Nakama env for LiveKit signing secrets. ⚠️ Deferred (runtime env getter not working in Lua on current host build)
3. Restart Nakama, validate RPC `livekit_token`. ✅
4. Deploy asset server room-state API updates.
5. Deploy client wrapper/plugin updates.
6. Validate 2-client then 6-client then 20-client test ladder.

## Validation checklist
- Token never signed in client.
- Host election stable after host leave.
- Ownership request/deny/grant works under contention.
- Disconnect cleanup obeys persist policy.
- Mid-session join reconstructs room state correctly.
- Save Room then restart restores `placed_saved` objects.

---

## Inputs Provided (already)
- Oracle SSH key path: `/Documents/privatessh-key-2025-11-20.key`
- LiveKit: self-hosted on Oracle via Docker
- Nakama: self-hosted on Oracle via Docker
- Plugin source paths:
  - Android Kotlin plugin present
  - Rust GDExtension present
- Token issuance decision: Nakama runtime RPC

---

## Immediate Next Patch Set (I will execute next)
1. Nakama runtime:
  - stabilize secret loading strategy (Vault/file/include) and remove hardcoded secret from Lua
  - keep `livekit_rpc.oracle.lua` as deployment source of truth
2. Ownership/snapshot:
  - implement host authority object registry + ownership request/transfer flow
  - implement late-join snapshot request/chunk/done
3. Wrapper/plugin:
  - topic-aware data APIs
  - reliable/unreliable surface consistency
