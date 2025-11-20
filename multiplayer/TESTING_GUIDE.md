# Quick Start: Testing New Multiplayer Features

## What's New? 🎉

1. **Avatar Sync** - See each other's custom painted heads
2. **Grabbable Sync** - Objects sync across network with ownership
3. **Voice Chat** - Talk to each other with 3D spatial audio!

## Quick Test (2 Devices, Same Network)

### Device 1 (Host)
1. Open game
2. Click "Host Game"
3. Paint your head (optional, but recommended)
4. Click "Send Avatar"
5. Click "Enable Voice"
6. Start talking!
7. Grab a ball or cube

### Device 2 (Client)  
1. Open game
2. Enter host's IP address (e.g., "192.168.1.100")
3. Click "Join Game"
4. Paint your head (different colors)
5. Click "Send Avatar"
6. Click "Enable Voice"
7. You should:
   - ✅ See host's avatar texture on their head
   - ✅ Hear host talking (voice comes from their position!)
   - ✅ See the ball/cube moving as host holds it
   - ❌ NOT be able to grab the ball while host holds it
   - ✅ See semi-transparent ball while host holds it

### Both Players
- Walk around - notice voice comes from the correct direction
- Release and re-grab objects - smooth ownership transfer
- Try grabbing same object - only one succeeds!

## Buttons Explained

| Button | What It Does |
|--------|--------------|
| **Host Game** | Create server (you're player 1) |
| **Join Game** | Connect to server as client |
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

## Performance Notes

- **Voice uses**: ~30 KB/s per talking player
- **8 players all talking**: ~240 KB/s = 2 Mbps (should be fine on WiFi)
- **Grabbed objects**: 20 updates/second per object
- **Avatar send**: One-time ~10 KB (only when clicking button or connecting)

## Known Limitations

1. **No voice compression** - Uses raw audio (future: Opus codec)
2. **No echo cancellation** - Use headphones or mute when not talking
3. **No push-to-talk** - Voice is always on when enabled
4. **Single-authority grabbables** - No collaborative carrying (yet)

## Next Features (Phase 4+)

- 🧱 Voxel build sync
- 🎫 Room codes (join by code instead of IP)
- 🎧 Voice compression (Opus)
- 📦 More optimized grabbable sync

---

**Everything working?** Great! Now you have a full VR multiplayer experience with avatars, object sync, and voice chat! 🎮🎤
