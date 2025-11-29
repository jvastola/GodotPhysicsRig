# Nakama Server Testing Guide

## Overview

This guide will walk you through testing the Nakama server connection from your Godot project and verifying that you can create and join multiplayer rooms.

## Prerequisites

✅ Nakama server running on Oracle Cloud (158.101.21.99)
✅ Godot project configured to connect to Oracle Cloud server
⚠️ **Oracle Cloud Security List firewall rules configured** (See FIREWALL_SETUP.md)

## Testing Steps

### Step 1: Configure Oracle Cloud Firewall

**CRITICAL:** You must complete this step first or testing will fail!

See [FIREWALL_SETUP.md](file:///C:/Users/Admin/GodotPhysicsRig/nakama/FIREWALL_SETUP.md) for detailed instructions.

Quick summary:
1. Sign in to Oracle Cloud Console
2. Navigate to Networking → VCN → Subnet → Security List
3. Add ingress rules for ports 7349, 7350, 7351

### Step 2: Verify Endpoint Access

Test from PowerShell to confirm firewall is configured:

```powershell
# Test healthcheck endpoint
Invoke-WebRequest -Uri "http://158.101.21.99:7350/healthcheck" -UseBasicParsing
```

**Expected result:** HTTP 200 with `{}` response

If this times out, the firewall is not configured correctly. Return to Step 1.

### Step 3: Test Admin Console

Open your browser and navigate to:
```
http://158.101.21.99:7351
```

**Login:**
- Username: `admin`
- Password: `password`

You should see the Nakama admin dashboard.

### Step 4: Run Nakama Test Scene in Godot

#### Option A: Run the Nakama Test Scene

1. Open your Godot project
2. Navigate to `multiplayer/nakama_test.tscn`
3. Run the scene (F6 or click Run Current Scene)

**What to expect:**
```
==== Nakama Multi-User Test ====
Initializing...
Starting authentication...
✓ Authentication successful!
  User ID: <your-user-id>
✓ WebSocket connected!
  Ready for multiplayer!
```

#### Option B: Test from Main Scene

If the main scene has Nakama integration:
1. Run the main scene
2. Look for Nakama connection logs in the console
3. Try creating or joining a room through the UI

### Step 5: Test Room Creation (Host)

In the Nakama Test scene:

1. Click **"Host Match"** button (or press 'H' key)
2. Watch the console output

**Expected output:**
```
[HOST] Creating match...
✓ Match created!
  Match ID: <match-id>
  Label: <room-code>
  >> Share this ID with other players!
Match: <match-id>
Players: 1 (you + 0 others)
```

The Match ID will be automatically filled in the "Join Match" input field for easy copying.

### Step 6: Test Room Joining (Client)

To test joining, you need to run a second instance:

1. **Run a second instance of Godot:**
   - Open another Godot editor instance
   - Or export and run the game separately
   - Each instance will get a unique device ID

2. In the second instance, paste the Match ID from the first instance
3. Click **"Join Match"** (or press 'J')

**Expected output in Instance 1 (Host):**
```
--- Match Presence Update ---
  + Player joined: <player-2-user-id>
Players: 2 (you + 1 others)
```

**Expected output in Instance 2 (Joining):**
```
[JOIN] Joining match: <match-id>
✓ Joined match: <match-id>
Players: 2 (you + 1 others)
```

### Step 7: Test Data Synchronization

Once both instances are in the same room:

1. In either instance, click **"Send Test Data"** (or press 'T')
2. Watch the other instance's console

**Expected output in sender:**
```
[TEST] Sending test data #1
→ Sent test data
```

**Expected output in receiver:**
```
← Received [TRANSFORM] from <sender-user-id>...
  Test ID: 1
  Position: {"x": 3.45, "y": 7.21, "z": 1.89}
```

✅ **Success!** If you see this, multiplayer synchronization is working!

### Step 8: Verify in Admin Console

1. Go to http://158.101.21.99:7351 in your browser
2. Log in (admin/password)
3. Navigate to **"Matches"** in the sidebar
4. You should see your active match listed with player count

### Step 9: Test from Main Scene

Now test the full game integration:

1. Close the test scenes
2. Run your main VR scene
3. Look for network/multiplayer UI
4. Try hosting or joining a room
5. Verify other players can see your avatar/actions

## Keyboard Shortcuts (Nakama Test Scene)

- **H** - Host a match
- **J** - Join match (using ID in text field)
- **L** - Leave match
- **T** - Send test data
- **V** - Send test voice data

## Common Issues and Solutions

### "Authentication failed"

**Cause:** Can't reach Nakama server

**Solutions:**
- Check Oracle Cloud firewall is configured (Step 1)
- Verify Nakama is running on server:
  ```bash
  ssh -i "C:\Users\Admin\Downloads\privatessh-key-2025-11-20.key" ubuntu@158.101.21.99
  docker ps | grep nakama
  ```

### "WebSocket disconnected"

**Cause:** Firewall blocking port 7350 or server issue

**Solutions:**
- Verify port 7350 is open in Oracle Cloud Security List
- Check Nakama logs:
  ```bash
  docker logs nakama --tail 50
  ```

### "Match not found" when joining

**Causes:**
- Incorrect Match ID
- Match expired (matches expire after inactivity)

**Solutions:**
- Copy the exact Match ID from the host
- Create a new match if the old one expired

### Players not seeing each other

**Cause:** State synchronization not implemented in main scene

**Solution:**
- Verify nakama_test scene works first (proves server is fine)
- Check main scene has code to handle `match_state_received` signal
- Ensure you're sending/receiving player transforms

## Expected Behavior Summary

✅ **Authentication:** 1-2 seconds
✅ **WebSocket connection:** Immediate after auth
✅ **Match creation:** Immediate
✅ **Match joining:** Immediate
✅ **State synchronization:** Real-time (< 100ms latency)
✅ **Multi-instance:** Each instance gets unique device ID

## Next Steps After Successful Testing

1. ✅ Integrate Nakama with your main VR scene
2. ✅ Implement player avatar synchronization
3. ✅ Add voice chat (if needed)
4. ✅ Test with friends over internet
5. ✅ Monitor server performance in admin console

## Files Modified

- [nakama_manager.gd](file:///C:/Users/Admin/GodotPhysicsRig/multiplayer/nakama_manager.gd) - Updated host to 158.101.21.99
- [nakama_test.gd](file:///C:/Users/Admin/GodotPhysicsRig/multiplayer/nakama_test.gd) - Test scene script
- [FIREWALL_SETUP.md](file:///C:/Users/Admin/GodotPhysicsRig/nakama/FIREWALL_SETUP.md) - Firewall configuration guide

## Server Connection Details

- **Host:** 158.101.21.99
- **HTTP/WebSocket Port:** 7350
- **Admin Console:** 7351
- **gRPC Port:** 7349 (optional)
- **Protocol:** HTTP (not HTTPS/SSL)

## Need Help?

1. Check [FIREWALL_SETUP.md](file:///C:/Users/Admin/GodotPhysicsRig/nakama/FIREWALL_SETUP.md) for firewall issues
2. Check Nakama logs on server: `docker logs nakama`
3. Check Nakama admin console  for active matches and errors
4. Verify server is running: `docker ps`
