# Quick Start: Testing New Multiplayer Features

## What's New? 🎉

1. **Avatar Sync** - See each other's custom painted heads
2. **Grabbable Sync** - Objects sync across network with ownership (optimized!)
3. **Voice Chat** - Talk to each other with 3D spatial audio (compressed!)
4. **Room Codes** - Join games with simple 6-character codes
5. **Voxel Build Sync** - Build together in real-time!

## Quick Test (2 Devices, Same Network)

### Device 1 (Host)
1. Open game
2. Make sure "Use Room Code" is checked
3. Click "Host Game"
4. **Share the 6-character room code shown on screen!**
5. Paint your head (optional, but recommended)
6. Click "Send Avatar"
7. Click "Enable Voice"
8. Start talking!
9. Grab a ball or cube
10. Place some voxels (if using VoxelTool)

### Device 2 (Client)  
1. Open game
2. Make sure "Use Room Code" is checked
3. **Enter the 6-character room code** from Device 1
4. Click "Join Room"
5. Paint your head (different colors)
6. Click "Send Avatar"
7. Click "Enable Voice"
8. You should:
   - ✅ See host's avatar texture on their head
   - ✅ Hear host talking (voice comes from their position!)
   - ✅ See the ball/cube moving as host holds it
   - ❌ NOT be able to grab the ball while host holds it
   - ✅ See semi-transparent ball while host holds it
   - ✅ See voxels appear when host places them
   
**Alternative:** Uncheck "Use Room Code" to join by IP address (old method)

### Both Players
- Walk around - notice voice comes from the correct direction
- Release and re-grab objects - smoother than before!
- Try grabbing same object - only one succeeds!
- Build voxels together - see instant replication
- Notice smoother object sync with adaptive update rates

## Buttons Explained

| Button | What It Does |
|--------|--------------|
| **Use Room Code** | Toggle between room code and IP-based joining |
| **Host Game** | Create server & generate room code |
| **Join Room** | Connect using 6-char room code |
| **Join Server** | Connect using IP (when room code off) |
| **Disconnect** | Leave the game |
| **Enable Voice** | Turn on microphone (others hear you) |
| **Disable Voice** | Turn off microphone (mute) |
| **Send Avatar** | Share your painted head texture |

## Troubleshooting

### "No head texture found"
- You haven't painted your head yet
- Use the GridPainter system to paint at least 1 pixel
- Then click "Send Avatar" again

### Can't grab object
- Another player is already holding it
- You'll see it semi-transparent
- Wait for them to release it!

### Voice not working (Windows)
1. Settings → Privacy & Security → Microphone
2. Make sure "Let apps access microphone" is ON
3. Restart Godot

### Remote player has default head
- They haven't sent their avatar yet
- Ask them to click "Send Avatar" button

## What You Should See

### Avatar Sync
- Remote player's head shows **their painted texture** (not the default sphere)
- Updates automatically when they connect
- Can manually update with "Send Avatar" button

### Grabbable Sync
- **While YOU hold object**: 
  - Object visible and solid for you
  - Others see it moving with you
  - Others see semi-transparent version
  
- **While OTHER holds object**:
  - You see semi-transparent version
  - You see it moving smoothly
  - You CANNOT grab it (try_grab returns false)

### Voice Chat
- **3D positioning**: Voice comes from player's head
- **Distance attenuation**: Quieter when far away
- **Multiple talkers**: All players can talk at once
- **Low latency**: ~100-200ms typical delay

## Performance Notes (Improved!)

- **Voice uses**: ~7.5 KB/s per talking player (4x compression via PCM16)
- **8 players all talking**: ~60 KB/s = 0.5 Mbps (much better!)
- **Grabbed objects**: Adaptive 5-20 Hz (slower when stationary)
- **Voxel builds**: Reliable sync, minimal bandwidth
- **Avatar send**: One-time ~10 KB (only when clicking button or connecting)

## Known Limitations

1. **Room codes are local-only** - No matchmaking server yet (works on LAN)
2. **No echo cancellation** - Use headphones or mute when not talking
3. **No push-to-talk** - Voice is always on when enabled
4. **Single-authority grabbables** - No collaborative carrying (yet)
5. **PCM16 compression** - Better than before, but not as good as Opus would be

## Completed Features ✅

- ✅ Voxel build sync - Build together in real-time
- ✅ Room codes - 6-character codes for easy joining (LAN only)
- ✅ Voice compression - PCM16 (4x smaller than before)
- ✅ Optimized grabbable sync - Adaptive update rates & delta compression

## Future Enhancements (Phase 5+)

- 🌐 Matchmaking server (room codes work globally, not just LAN)
- 🎧 True Opus codec (requires GDExtension)
- 🎙️ Push-to-talk support
- 🤝 Collaborative object carrying
- 📊 Network stats overlay (ping, bandwidth, packet loss)

---

**Everything working?** Great! Now you have a full VR multiplayer experience with avatars, object sync, and voice chat! 🎮🎤
