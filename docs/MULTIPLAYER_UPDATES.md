# Multiplayer Updates - Matchmaking & Bug Fixes

## Completed Features

### 1. ✅ Global Matchmaking Server (HIGHEST PRIORITY)
Replaced LAN-only room codes with HTTP-based global matchmaking system.

**New File:** `multiplayer/matchmaking_server.gd`
- HTTPRequest client mode: Query remote matchmaking servers
- TCPServer hosting mode: Run as standalone matchmaking server
- JSON API endpoints:
  - `POST /room` - Register room with code, host name
  - `GET /room/{code}` - Lookup room by 6-char code
  - `DELETE /room/{code}` - Unregister room
  - `GET /rooms` - List all active rooms
- Room expiry after 3600 seconds (1 hour)
- Automatic cleanup of expired rooms

**Modified:** `multiplayer/network_manager.gd`
- Added matchmaking integration in `_setup_matchmaking()`
- Rooms auto-register with matchmaking server when created
- `join_by_room_code()` queries matchmaking server for room details
- Auto-unregister room from matchmaking on disconnect
- Signal handlers: `_on_matchmaking_room_found()`, `_on_matchmaking_room_registered()`

**Modified:** `multiplayer/network_ui.gd`
- Updated `_on_join_pressed()` to call `join_by_room_code()` when using room codes
- Room codes now work globally, not just on LAN

**Configuration:**
- Matchmaking server URL: `http://localhost:8080` (default)
- Change `MATCHMAKING_SERVER_URL` in network_manager.gd to use remote server
- To run standalone matchmaking server: Call `matchmaking.start_local_server(8080)`

### 2. ✅ Fixed Voice Self-Hearing
Players no longer hear their own voice when alone or with others.

**Modified:** `multiplayer/network_manager.gd`
- Added check in `_receive_voice_data()`: `if sender_id == get_multiplayer_id(): return`
- Voice data from local player is now ignored

### 3. ✅ Voice Enabled by Default
Voice chat is now enabled automatically when joining/hosting.

**Modified:** `multiplayer/network_manager.gd`
- Set `voice_enabled = true` in `_ready()` function

### 4. ✅ Initial Voxel State Sync
New clients now see all existing voxels immediately upon joining.

**Modified:** `voxel_chunk_manager.gd`
- Added `get_all_voxels()` function to export all voxel positions and colors
- Returns Array of Dictionaries: `[{"pos": Vector3, "color": Color}, ...]`

**Modified:** `multiplayer/network_manager.gd`
- Server calls `_sync_voxel_state_to_client()` RPC when new player connects
- Queries voxel manager for all voxels and sends via `_receive_voxel_state()` RPC
- Client receives full voxel state and emits `voxel_placed_network` signals for each

**Modified:** `XRPlayer.tscn`
- Added VoxelChunkManager to "voxel_manager" group for easy lookup

## Testing Instructions

### Local Testing (LAN):
1. Host a game with room codes enabled
2. Note the 6-character room code
3. Join from another client using the room code
4. Verify: Voice works, no self-hearing, voxels sync immediately

### Global Testing (Internet):
1. Run matchmaking server on a VPS or public server:
   ```gdscript
   var matchmaking = MatchmakingServer.new()
   matchmaking.start_local_server(8080)
   ```
2. Update `MATCHMAKING_SERVER_URL` in network_manager.gd to server IP
3. Host game on one network, join from another network using room code
4. Verify global connectivity works

## Technical Details

### Matchmaking Flow:
1. **Host creates server:**
   - Generates 6-char room code (A-Z, 2-9, excluding confusing chars)
   - Calls `matchmaking.register_room(code, ip, port, host_name)`
   - Matchmaking sends `POST http://server:8080/room` with JSON body
   - Server stores: `{code: {ip, port, host_name, timestamp}}`

2. **Client joins by code:**
   - Enters 6-char room code in UI
   - Calls `network_manager.join_by_room_code(code)`
   - Matchmaking sends `GET http://server:8080/room/{code}`
   - Server responds with `{ip, port, host_name}` if found
   - Client connects to match via Nakama relay

3. **Host disconnects:**
   - Calls `matchmaking.unregister_room(code)`
   - Matchmaking sends `DELETE http://server:8080/room/{code}`
   - Server removes room from registry

### Voxel Sync Flow:
1. **New client connects:**
   - Server's `_on_peer_connected()` detects new client
   - Calls `_sync_voxel_state_to_client()` RPC to self (authority check)
   - Queries VoxelChunkManager via `get_all_voxels()`
   - Sends array of voxel data to client via `_receive_voxel_state()` RPC

2. **Client receives state:**
   - `_receive_voxel_state()` processes array
   - Emits `voxel_placed_network` signal for each voxel
   - VoxelChunkManager's `_on_network_voxel_placed()` adds voxels locally

## Network Bandwidth

### Voice Chat (per player):
- PCM16 compression: ~7.5 KB/s (was 30 KB/s uncompressed)
- Sample rate: 16kHz stereo
- Unreliable RPC: Allows packet loss for real-time performance

### Grabbable Objects:
- Delta compression: Only send if moved > 1cm
- Adaptive rate: 5-20Hz based on activity
- Fast movement: 20Hz (50ms), Slow/static: 5Hz (200ms)

### Voxel Builds:
- Reliable RPC: Guaranteed delivery
- Initial sync: One-time full state on connect (N voxels × ~24 bytes each)
- Incremental: Single voxel add/remove per action

## Known Limitations

1. **Matchmaking server persistence:** Room registry is in-memory only. Restart clears all rooms.
2. **Room code validation:** 6 characters only. System generates codes but doesn't prevent conflicts.
3. **Voxel colors:** Currently all synced as white (Color.WHITE). Color sync needs voxel manager enhancement.
4. **NAT traversal:** Direct IP connections still require port forwarding. Future: Add NAT punch-through or relay server.

## Next Steps (Optional)

1. **Persistent matchmaking:** Use database (SQLite/PostgreSQL) for room registry
2. **Room browser:** UI to list all active rooms, not just join by code
3. **Voxel color sync:** Store and sync actual voxel colors in chunk manager
4. **NAT punch-through:** Implement STUN/TURN for easier connectivity
5. **Matchmaking authentication:** Add API keys or tokens to prevent abuse
6. **Room metadata:** Max players, game mode, map name, etc.

## Files Changed

### New Files:
- `multiplayer/matchmaking_server.gd` (283 lines)

### Modified Files:
- `multiplayer/network_manager.gd` (+50 lines, 4 new functions)
- `multiplayer/network_ui.gd` (~10 lines modified)
- `voxel_chunk_manager.gd` (+9 lines, 1 new function)
- `XRPlayer.tscn` (added group)

### Documentation:
- `MULTIPLAYER_UPDATES.md` (this file)
