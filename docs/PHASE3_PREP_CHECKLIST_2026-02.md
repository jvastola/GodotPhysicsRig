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

## Rust Plugin Work Needed (Next)
- Add GDExtension methods to match wrapper assumptions:
  - `send_reliable_data(data: GString)`
  - `send_unreliable_data(data: GString)`
  - `send_data_to(data: GString, identity: GString, reliable: bool)`
- Emit inbound data with sender + payload + topic equivalent.
- If binary payload support is added in Rust, update wrapper fallback that currently UTF-8 encodes payload.

## Topic Conventions (Proposed)
- `rep/transform` high-rate unreliable
- `rep/object` object deltas (mostly unreliable)
- `rep/property` reliable on-change
- `ctrl/ownership` reliable control messages
- `ctrl/snapshot` reliable snapshot chunks

## Validation Plan Before Full Phase 3
1. Android: verify all four send methods are callable from Godot and reach remote peer.
2. Wrapper: verify `data_packet_received` includes non-empty topic on Android path.
3. Rust desktop: verify fallback methods still send/receive with current plugin.
4. Mixed test: keep Nakama control-plane active while mirroring one replication topic over LiveKit.

## Android/Desktop Parity Matrix (Pre-Phase-3 Gate)
- `Connect/disconnect room`: Android ✅ / Desktop ✅
- `Reliable broadcast send`: Android ✅ (`sendDataReliable`) / Desktop ✅ (`send_reliable_data` scaffold)
- `Unreliable broadcast send`: Android ✅ (`sendDataUnreliable`) / Desktop ⚠️ currently aliases reliable/chat fallback
- `Reliable targeted send`: Android ✅ (`sendDataToReliable`) / Desktop ⚠️ currently broadcast fallback
- `Unreliable targeted send`: Android ✅ (`sendDataToUnreliable`) / Desktop ⚠️ currently broadcast fallback
- `Inbound topic preserved`: Android ✅ (RoomEvent.DataReceived topic) / Desktop ⚠️ pending native data event export
- `Wrapper packet signal`: Android ✅ / Desktop ⚠️ currently compatibility path only

## Parity Requirements Before Phase 3 Full Cutover
1. Rust plugin emits native `data_received(identity, payload, topic)` signal.
2. Rust plugin differentiates reliable vs unreliable publish.
3. Rust plugin supports targeted data publish.
4. Wrapper marks `reliable` accurately on receive path for both platforms.
