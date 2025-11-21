# Oracle Cloud Matchmaking - Quick Test Guide

## ✅ Server Status

Your matchmaking server is **LIVE** and working at:
- **URL**: `http://158.101.21.99:8080`
- **Status**: Running (uptime: 8+ minutes)

## ✅ Verified Working

All endpoints tested and confirmed working:
- ✅ Health check
- ✅ Room registration
- ✅ Room lookup
- ✅ Room listing
- ✅ Room deletion

## How to Test with Godot

### 1. Launch Two Game Instances

**Instance 1 (Host):**
1. Open your game
2. Go to NetworkUI
3. Click "Host Game"
4. Note the room code that appears

**Instance 2 (Client):**
1. Open another instance of your game
2. Go to NetworkUI
3. Enter the room code from Instance 1
4. Click "Join Game"

Both clients will now communicate through your Oracle Cloud matchmaking server!

## Verify Server Activity

You can monitor your server by SSH-ing into your Oracle Cloud instance:

```bash
ssh ubuntu@158.101.21.99
cd ~/godotmatchmaking  # or wherever you deployed
docker logs -f godot-matchmaking
```

You'll see logs like:
```
Room registered: ABC123 (your.ip:7777) by PlayerName
Room lookup: ABC123
```

## Test Endpoints Manually

```bash
# Check server health
curl http://158.101.21.99:8080/health

# List active rooms
curl http://158.101.21.99:8080/rooms

# Register a test room
curl -X POST http://158.101.21.99:8080/room \
  -H "Content-Type: application/json" \
  -d '{"room_code":"TEST","ip":"0.0.0.0","port":7777,"host_name":"Me"}'

# Look up the room
curl http://158.101.21.99:8080/room/TEST

# Delete the room
curl -X DELETE http://158.101.21.99:8080/room/TEST
```

## Updated Files

- **[`multiplayer/matchmaking_server.gd`](file:///Users/johnnyvastola/GodotPhysicsRig/multiplayer/matchmaking_server.gd)** 
  - Now points to `http://158.101.21.99:8080`
  - Cleaned up JSON payload
  - Better logging

## Next Steps

Your matchmaking is fully operational! You can now:

1. **Test multiplayer** across different networks
2. **Share room codes** with friends anywhere
3. **Monitor usage** through Oracle Cloud logs
4. **Scale up** if needed (add more instances)

## Troubleshooting

If connections fail:
- Check firewall: Port 8080 should be open
- Verify server is running: `curl http://158.101.21.99:8080/health`
- Check Godot console for errors
- Review server logs on Oracle Cloud

## Success! 🎉

Your Godot game now has cloud-based matchmaking running on Oracle Cloud!
