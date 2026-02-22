# Nakama Multi-User Test Guide

## Setup

### 1. Ensure Nakama Server is Running

```bash
cd nakama
docker ps  # Should show nakama and postgres containers
```

If not running:
```bash
docker-compose up -d
```

### 2. Open the Test Scene

In Godot:
- Navigate to `res://multiplayer/client/scenes/nakama_test.tscn`
- Open the scene
- Press F6 to run

## Test Procedure

### Test 1: Single Instance Authentication

**Expected Result:**
1. Window shows "Authenticating..."
2. Console shows "✓ Authentication successful!"
3. Console shows "✓ WebSocket connected!"
4. Status shows "Connected - Ready!"
5. Buttons become enabled

**If it fails:**
- Check Nakama server is running: `docker ps`
- Check logs: `docker logs nakama`
- Verify port 7350 is accessible

### Test 2: Two Instance Matchmaking

**Instance 1 (Host):**
1. Click "Create Match" button (or press H)
2. Note the Match ID in console
3. Copy the Match ID from the input field

**Instance 2 (Client):**
1. Paste Match ID into input field
2. Click "Join" button (or press J)
3. Should see "✓ Joined match"

**Expected Result:**
- Instance 1 sees: "+ Player joined: [user_id]"
- Instance 2 sees: "✓ Joined match"
- Both show "Players: 2"

### Test 3: State Synchronization

**On either instance:**
1. Click "Send Test Data" (or press T multiple times)

**Expected Result:**
- Sending instance shows: "→ Sent test data #N"
- Receiving instance shows: "← Received [TRANSFORM] from..."
- Console shows position data

### Test 4: Player Leave/Rejoin

**Instance 2:**
1. Click "Leave Match" (or press L)

**Expected Result:**
- Instance 2: "Left match"
- Instance 1: "- Player left: [user_id]"
- Both update player count

**Then rejoin:**
- Instance 2: Enter same Match ID and click Join
- Should rejoin successfully

### Test 5: Three+ Players

**Repeat Test 2 setup for Instance 3, 4, etc.**

Each instance should:
- See all other players join
- Receive test data from all players
- Show correct player count

## Console Output Reference

### Good Output

```
==== Nakama Multi-User Test ====
Authenticating...
✓ Authentication successful!
  User ID: dd8da55d-...
✓ WebSocket connected!
  Ready for multiplayer!

[HOST] Creating match...
✓ Match created!
  Match ID: 5a4c8e2f-...
  >> Share this ID with other players!

  + Player joined: abc123...
--- Match Presence Update ---

[TEST] Sending test data #1
→ Sent test data
← Received [TRANSFORM] from def456...
  Test ID: 1
  Position: (1.23, 4.56, 7.89)
```

### Problem Indicators

**"Authentication failed"**
- Server not running or not accessible
- Check `docker logs nakama`

**"WebSocket disconnected"**
- Network issue or server restarted
- Should auto-reconnect

**"Match error"**
- Invalid match ID
- Match may have expired

## Automated Test Checklist

Use this checklist to verify all functionality:

- [ ] **Authentication**
  - [ ] Device ID generated/loaded
  - [ ] HTTP authentication succeeds
  - [ ] JWT token received
  
- [ ] **WebSocket**
  - [ ] Connection established
  - [ ] Auto-connects after auth
  - [ ] Reconnects on disconnect
  
- [ ] **Match Creation**
  - [ ] Can create match
  - [ ] Receive valid match ID
  - [ ] Match ID is displayed
  
- [ ] **Match Joining**
  - [ ] Can join with valid ID
  - [ ] Cannot join with invalid ID
  - [ ] Can rejoin after leaving
  
- [ ] **Presence**
  - [ ] See other players join
  - [ ] See other players leave
  - [ ] Player count accurate
  
- [ ] **State Sync**
  - [ ] Can send data
  - [ ] Can receive data
  - [ ] Data arrives correctly
  - [ ] Works with multiple players
  
- [ ] **UI**
  - [ ] Buttons enable/disable correctly
  - [ ] Status updates accurately
  - [ ] Console logs properly
  - [ ] Match info displayed

## Performance Metrics

Monitor these during testing:

**Latency:**
- Local: < 10ms
- Regional: 20-50ms
- Cross-continent: 100-200ms

**Message Rate:**
- Should handle 60+ updates/sec per player
- No dropped messages
- Order preserved

**Stability:**
- No disconnects during test
- Auto-reconnect works if disconnected
- No memory leaks over time

## Troubleshooting

### "Cannot create match"
- Wait for WebSocket connection
- Check console for errors
- Restart Nakama: `docker-compose restart nakama`

### "Cannot receive messages"
- Verify both in same match
- Check match IDs match exactly
- Try sending from other instance

### "Players count wrong"
- Normal - includes self in count
- Refreshes on presence updates
- May lag slightly

### "High latency"
- Expected for localhost: < 10ms
- Check server load: `docker stats`
- Monitor network: Activity Monitor

## Next Steps After Testing

Once all tests pass:

1. **Integrate with your game**
   - Add to MainScene
   - Replace P2P networking
   - Use for player transforms

2. **Deploy to cloud**
   - Follow `nakama/ORACLE_CLOUD_DEPLOY.md`
   - Update `nakama_host` in nakama_manager.gd
   - Enable SSL

3. **Add features**
   - Voice chat via Nakama
   - Leaderboards
   - Friend lists
   - Cloud save

## Success Criteria

All tests pass when:
- ✅ 2+ instances can authenticate
- ✅ All instances connect WebSocket
- ✅ Can create and join matches
- ✅ State syncs between all players
- ✅ Players see accurate presence
- ✅ No errors in console
- ✅ Stable for 5+ minutes

**If all checks pass, Nakama integration is production-ready!** 🎉
