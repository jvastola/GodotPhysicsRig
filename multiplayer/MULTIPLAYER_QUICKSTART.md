# Multiplayer System - Quick Start Guide

## Overview
This VR multiplayer system uses ENet for low-latency peer-to-peer networking. It synchronizes player head, hand positions, and player scale across all connected clients at 20Hz.

## Files Created

### Core Networking
- **`multiplayer/network_manager.gd`** - Singleton autoload that manages all network connections
  - Handles hosting/joining servers
  - Manages player data dictionary
  - Sends/receives player transform updates via RPC
  - Emits signals for connection events

- **`multiplayer/network_player.gd`** - Visual representation of remote players
  - Interpolates transforms smoothly at 15 fps
  - Shows head, hands, and body meshes
  - Displays player ID label above head
  - Updates from NetworkManager's player data

- **`multiplayer/NetworkPlayer.tscn`** - Scene for remote player visuals

### UI
- **`multiplayer/network_ui.gd`** - Control panel for hosting/joining
- **`multiplayer/NetworkUI.tscn`** - 2D UI scene with buttons and status display
- **`multiplayer/network_ui_viewport_3d.gd`** - 3D world-space viewport wrapper
- **`multiplayer/NetworkUIViewport3D.tscn`** - 3D scene with NetworkUI rendered to SubViewport

### Integration
- **`xr_player.gd`** - Modified to:
  - Send local player transforms to NetworkManager (20Hz)
  - Spawn/despawn remote players on connect/disconnect
  - Update remote player visuals every frame

- **`project.godot`** - Added NetworkManager as autoload singleton

## How to Test

### Single Computer (Local Testing)
1. **Launch two instances of the game:**
   - In Godot editor, click "Run Project" (F5)
   - Export the project and run the executable separately
   - OR use command line: `godot --path . &` (twice)

2. **First instance - Host:**
   - Press "Host Game" button
   - Default port is 7777

3. **Second instance - Client:**
   - Enter "127.0.0.1" in address field
   - Enter "7777" in port field
   - Press "Join Game" button

4. **Verify synchronization:**
   - Move around in VR/desktop mode
   - You should see the other player's head and hands moving
   - Scale changes should be visible on remote players

### Two Computers (Network Testing)
1. **Find host IP address:**
   - Windows: `ipconfig` (look for IPv4 Address)
   - Linux/Mac: `ifconfig` or `ip addr`

2. **Host computer:**
   - Press "Host Game" button
   - Note your local IP address

3. **Client computer:**
   - Enter host's IP address (e.g., "192.168.1.100")
   - Enter port "7777"
   - Press "Join Game"

4. **Firewall:**
   - Ensure port 7777 (UDP) is open on host computer
   - Windows: Allow Godot through Windows Defender Firewall
   - Linux: `sudo ufw allow 7777/udp`

## Adding NetworkUI to Your Scene

The NetworkUI is already included as a 3D world-space panel in MainScene. You can interact with it using the hand pointer in VR or mouse in desktop mode.

**To add it to other scenes:**

Via editor:
1. Open your scene in Godot
2. Click "+" to add a child node
3. Use "Instantiate Child Scene"
4. Select `multiplayer/NetworkUIViewport3D.tscn`
5. Position it in the world (default position is at (3.2, 1, 2) facing the spawn)

Via code:
```gdscript
var network_ui = preload("res://multiplayer/NetworkUIViewport3D.tscn").instantiate()
network_ui.position = Vector3(3, 1.5, 2)  # Position in front of player
add_child(network_ui)
```

## Technical Details

### Update Rates
- **Player transforms**: 20Hz (50ms intervals) via unreliable RPC
- **Visual interpolation**: 15 fps smoothing on remote players
- **Connection events**: Reliable RPC

### Network Architecture
- **Protocol**: ENet (UDP-based)
- **Topology**: Player-hosted listen server (host is also a player)
- **Max players**: 8 (configurable in network_manager.gd)
- **Port**: 7777 (default, configurable)

### Synchronized Data Per Player
- Head position (Vector3)
- Head rotation (Vector3 - Euler angles)
- Left hand position (Vector3)
- Left hand rotation (Vector3)
- Right hand position (Vector3)
- Right hand rotation (Vector3)
- Player scale (Vector3)

### Bandwidth Estimate
- Per player update: ~84 bytes (7 Vector3s × 12 bytes)
- At 20Hz: ~1.68 KB/s per player
- For 8 players: ~13.44 KB/s total (host receives all)

## Troubleshooting

### "NetworkManager not found" error
- Ensure project.godot has NetworkManager in autoload section
- Restart Godot editor after modifying project.godot

### Players not appearing
- Check that XRPlayer scene is in the scene tree
- Verify NetworkManager signals are connected
- Check console for "Spawned remote player" messages

### Connection failed
- Verify IP address is correct
- Check firewall settings on host computer
- Ensure both computers are on same network (for LAN)
- Try hosting on client computer instead

### Jittery movement
- Increase `interpolation_speed` in network_player.gd
- Decrease `update_rate` in xr_player.gd (lower = more frequent)
- Check network latency with ping

### Remote players not at correct scale
- Verify player_body.scale is being set correctly
- Check that scale synchronization is working in _update_networking()

### Connection quality issues
- Check the connection quality indicator in NetworkUI
- If quality is "Poor" or "Fair", try reducing graphics quality
- Use network stats to identify if ping or bandwidth is the issue
- Enable push-to-talk mode to reduce bandwidth (voice always-on uses ~7.5 KB/s)

## New Features (Latest Update)

### Connection Quality Monitoring
NetworkManager now tracks network statistics in real-time:
- **Ping tracking**: Monitor latency to server
- **Bandwidth monitoring**: Track upload/download speeds
- **Connection quality**: Automatically categorized as Excellent/Good/Fair/Poor
- **Quality signals**: React to connection changes in your code

```gdscript
# Get current network stats
var stats = NetworkManager.get_network_stats()
print("Ping: ", stats["ping_ms"], "ms")
print("Bandwidth Up: ", stats["bandwidth_up"], " KB/s")
print("Quality: ", NetworkManager.get_connection_quality_string())

# Connect to quality change signal
NetworkManager.connection_quality_changed.connect(_on_quality_changed)

func _on_quality_changed(quality: int):
    if quality >= 2:  # FAIR or POOR
        print("Warning: Connection quality degraded!")
```

### Push-to-Talk Voice Chat
Voice chat now defaults to push-to-talk mode for better bandwidth management:
- **Default key**: Spacebar (configurable)
- **Three modes**: Always On, Push to Talk, Voice Activated
- **Visual indicator**: NetworkUI shows when voice is transmitting

```gdscript
# Change voice mode
NetworkManager.set_voice_activation_mode(NetworkManager.VoiceMode.ALWAYS_ON)

# Change push-to-talk key
NetworkManager.set_push_to_talk_key(KEY_T)

# Check if voice is currently transmitting
if NetworkManager.is_voice_transmitting():
    print("Voice active!")
```

### Automatic Reconnection
NetworkManager now automatically attempts to reconnect if connection is lost:
- **Timeout detection**: 10 seconds (configurable)
- **Exponential backoff**: Waits longer between attempts
- **Max attempts**: 5 (configurable)
- **State preservation**: Attempts to restore session state

### Standalone QWERTY Keyboard
A fully-featured virtual keyboard component for text input:
- **Full QWERTY layout** with all letters, numbers, and symbols
- **Shift and Caps Lock** support
- **Reusable component** for any text input needs
- **Already integrated** into NetworkUI for room code entry

```gdscript
# Use the keyboard in your own scenes
var keyboard = preload("res://src/ui/KeyboardQWERTY.tscn").instantiate()
keyboard.max_length = 20
keyboard.text_submitted.connect(_on_text_entered)
add_child(keyboard)

func _on_text_entered(text: String):
    print("User entered: ", text)
```

See `docs/KEYBOARD_USAGE.md` for full keyboard documentation.

### Network Stats Display in UI
NetworkUI now shows real-time network statistics (if stats nodes exist in scene):
- **Ping**: Current latency in milliseconds
- **Bandwidth**: Upload/download speeds
- **Connection quality**: Color-coded indicator (Green/Yellow/Red)
- **Voice status**: Shows when push-to-talk is active

## Next Steps

1. **Add grabbable synchronization** (Phase 3 of roadmap)
2. **Implement voice chat** (Phase 5 of roadmap)
3. **Add room codes** (Phase 6 of roadmap)
4. **Optimize bandwidth** with state delta compression
5. **Add client-side prediction** for smoother local movement

## Code Example: Accessing NetworkManager

```gdscript
# Get NetworkManager from anywhere
var net_mgr = get_node("/root/NetworkManager")

# Check if connected
if net_mgr.peer:
    print("Connected with ID: ", net_mgr.get_multiplayer_id())

# Check if we're the host
if net_mgr.is_server():
    print("We are hosting")

# Get all connected players
for peer_id in net_mgr.players.keys():
    print("Player ", peer_id, " is connected")
```

## Signals You Can Connect To

```gdscript
NetworkManager.player_connected.connect(_on_player_joined)
NetworkManager.player_disconnected.connect(_on_player_left)
NetworkManager.connection_succeeded.connect(_on_we_connected)
NetworkManager.connection_failed.connect(_on_we_failed)
NetworkManager.server_disconnected.connect(_on_host_left)
```
