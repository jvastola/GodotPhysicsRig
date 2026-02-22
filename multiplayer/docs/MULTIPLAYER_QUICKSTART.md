# Multiplayer System - Quick Start Guide (Nakama)

## Overview
This VR multiplayer system uses **Nakama** for scalable, real-time networking. It synchronizes player transforms, grabbable objects, and voxel updates via a global cloud relay, removing the need for direct IP connections or port forwarding.

## Core Components

### 1. Networking Central
- **`multiplayer/network_manager.gd`**: The core singleton managing all network state.
  - Handles match joined/left events.
  - Manages the global `players` dictionary (uses Nakama User IDs).
  - Synchronizes transforms and state via Nakama Match State op-codes.
  - No longer uses ENet or Peer-to-Peer RPCs.

### 2. Matchmaking
- **`multiplayer/nakama_manager.gd`**: Handles the underlying WebSocket connection to the Nakama server (Oracle Cloud).
  - Performs device-based authentication.
  - Lists, creates, and joins matches.

### 3. Visuals & Local Integration
- **`multiplayer/network_player.gd`**: Interpolates and renders remote players.
- **`src/player/components/player_network_component.gd`**: Bridges the local XRPlayer state to the `NetworkManager`.

## How to Test

### Setup
1. Ensure you have an internet connection (connects to Nakama on Oracle Cloud).
2. Launch two instances of the project.

### Hosting (Creating a Match)
1. Open the **Network UI** in the world.
2. Wait for "Ready to connect" (Authentication takes ~1s).
3. Press **"Host Game"**.
4. The system will create a match and display a **Match ID** (e.g., a long UUID string).

### Joining
1. On the second instance, wait for authentication.
2. **Option A (Manual)**: Enter the Match ID into the input field and press **"Join Game"**.
3. **Option B (Browser)**: Press the **Refresh** button on the Room List to see active matches, then click **"Join"** next to the desired match.

## Technical Details

### Identity & Synchronization
- **Primary Key**: Nakama `user_id` (String).
- **Update Rate**: 20Hz (50ms) for movement; event-driven for grabs/voxels.
- **Protocol**: WebSocket (TLS) for relay; WebRTC for LiveKit spatial voice.

### Port Requirements
- None. Communications are outbound to Nakama (default port 7350). No port forwarding is required for clients or hosts.

## Next Steps
- **Grabbable Objects**: Interactions are automatically synced via Match State.
- **Voice Chat**: Spatial audio is handled by the **LiveKit** integration (integrated into the same lobby system).
- **Voxel Building**: Voxel placements/removals are synced globally.
