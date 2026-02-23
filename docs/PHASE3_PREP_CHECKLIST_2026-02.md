# Phase 3 Prep Checklist (LiveKit DataChannel)

## Goal
Prepare a stable contract for moving realtime replication traffic from Nakama relay messages to LiveKit DataChannel while keeping backward compatibility.

## Wrapper Contract (Implemented)
- File: `src/livekit_wrapper.gd`
- Added packet-level API (pre-Phase-3 scaffold):
  - `send_packet(payload, topic, reliable)`
  - `send_packet_to(payload, identity, topic, reliable)`
  - `send_text_topic(data, topic, reliable)`
  - `send_text_topic_to(data, identity, topic, reliable)`
  - `send_json_packet(payload, topic, reliable)`
- Added packet receive signal:
  - `data_packet_received(sender_identity, payload, topic, reliable)`
- Kept existing compatibility signal:
  - `data_received(sender_identity, data)`

## Android Plugin Surface (Implemented)
- File: `multiplayer/plugins/livekit-android/src/main/kotlin/com/jvastola/physicshand/livekit/GodotLiveKitPlugin.kt`
- Added methods for reliability-aware publish:
  - `sendDataReliable(data, topic)`
  - `sendDataUnreliable(data, topic)`
  - `sendDataToReliable(data, identity, topic)`
  - `sendDataToUnreliable(data, identity, topic)`
- Existing methods remain compatible:
  - `sendData(...)` delegates to reliable
  - `sendDataTo(...)` delegates to reliable targeted send

## Rust Plugin Surface (Implemented Locally)
- File: `multiplayer/plugins/godot-livekit/rust/src/livekit_client.rs`
- Added user-data publish methods:
  - `send_reliable_data(...)`
  - `send_unreliable_data(...)`
  - `send_data_to(...)`
  - topic-aware variants:
    - `send_reliable_data_topic(...)`
    - `send_unreliable_data_topic(...)`
    - `send_data_to_topic(...)`
- Added inbound data signal:
  - `data_received(sender_identity, payload, topic)`
- Switched desktop data path from chat fallback to `LocalParticipant.publish_data(DataPacket)` for replication traffic.
- Note: this plugin path is currently ignored by top-level git (`multiplayer/plugins/godot-livekit`), so plugin changes are local unless the plugin repo is committed separately.

## Topic Conventions (Proposed)
- `rep/transform` high-rate unreliable
- `rep/object` object deltas (mostly unreliable)
- `rep/property` reliable on-change
- `ctrl/ownership` reliable control messages
- `ctrl/snapshot` reliable snapshot chunks

## Validation Plan Before Full Phase 3
1. Android: verify all four send methods are callable from Godot and reach remote peer.
2. Wrapper: verify `data_packet_received` includes non-empty topic on Android path.
3. Rust desktop: verify native data methods send/receive and topic is preserved.
4. Mixed test: keep Nakama control-plane active while mirroring one replication topic over LiveKit.
5. Rate policy: verify player + held object update send paths are capped at 20Hz.

## Android/Desktop Parity Matrix (Pre-Phase-3 Gate)
- `Connect/disconnect room`: Android ✅ / Desktop ✅
- `Reliable broadcast send`: Android ✅ (`sendDataReliable`) / Desktop ✅ (`send_reliable_data`)
- `Unreliable broadcast send`: Android ✅ (`sendDataUnreliable`) / Desktop ✅ (`send_unreliable_data`)
- `Reliable targeted send`: Android ✅ (`sendDataToReliable`) / Desktop ✅ (`send_data_to`)
- `Unreliable targeted send`: Android ✅ (`sendDataToUnreliable`) / Desktop ✅ (`send_data_to` with `reliable=false`)
- `Inbound topic preserved`: Android ✅ (RoomEvent.DataReceived topic) / Desktop ✅ (RoomEvent::DataReceived topic)
- `Wrapper packet signal`: Android ✅ / Desktop ✅ (`src/livekit_wrapper.gd` now wires Rust `data_received`)

## Parity Requirements Before Phase 3 Full Cutover
1. Run desktop Rust build in an environment with network access to LiveKit WebRTC artifact host.
2. Run Android plugin build on a machine with a JDK installed.
3. Optional: add receive-path reliability metadata to wrapper signal for exact parity with send-path reliability controls.

## Current Main-Repo State (2026-02-23)
- LiveKit topics now wired in `network_manager.gd`:
  - `rep/transform`
  - `rep/object`
  - `rep/property`
- Manifest/property scaffolding is in place:
  - register/get manifest APIs
  - property replication API with owner checks and property sequence tracking
  - direct node apply hook for replicated property changes
- Current rate policy in client:
  - player transform = 20Hz
  - held object transform = 20Hz

## Remaining Execution Order
1. Build and publish plugin binaries (Android + desktop Rust).
2. Validate 2-instance mixed replication (`rep/object`, `rep/transform`, `rep/property`) with ownership contention.
3. Run 6-peer soak with metrics capture and verify no desync/ownership regressions.
4. Promote LiveKit data replication feature flag from opt-in test mode toward default-on after soak pass.
