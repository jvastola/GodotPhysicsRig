# Nakama Integration for Godot VR Multiplayer

Production-ready game server solution for scalable multiplayer VR experiences. Replaces P2P networking with relay-based architecture that works through any NAT/firewall.

## Features

- ✅ **No Port Forwarding Required** - Works through any NAT/firewall
- ✅ **Scalable to 10k+ Users** - Battle-tested in production games
- ✅ **Matchmaking** - Built-in room creation and discovery
- ✅ **Authentication** - Device ID, email, or social login
- ✅ **Real-time Relay** - Low-latency multiplayer networking
- ✅ **Social Features** - Friends, chat, presence (future)
- ✅ **Leaderboards** - Competitive features (future)

## Quick Start

### 1. Start Nakama Server Locally

```bash
cd nakama
docker-compose up
```

**Ports:**
- `7350` - Game client connection (WebSocket)
- `7351` - Admin console (web UI)
- `5432` - PostgreSQL database

**Admin Console:** http://localhost:7351
- Username: `admin`
- Password: `password`

### 2. In Godot

The Nakama SDK is already integrated. Usage:

```gdscript
# Get the Nakama manager
var nakama = get_node("/root/NakamaManager")

# Authenticate (device ID - no account needed)
await nakama.authenticate_device()

# Create a match
await nakama.create_match()

# Join a match by code
await nakama.join_match("ROOM_CODE")
```

## Architecture

```
┌──────────────┐
│ Godot Client │───┐
└──────────────┘   │
                   │ WebSocket
┌──────────────┐   │
│ Godot Client │───┤
└──────────────┘   │
                   ▼
              ┌─────────────┐
              │   Nakama    │
              │   Server    │
              └──────┬──────┘
                     │
              ┌──────▼──────┐
              │ PostgreSQL  │
              └─────────────┘
```

**How It Works:**
1. All clients connect to Nakama server via WebSocket
2. Nakama relays messages between clients
3. No direct P2P connection needed
4. Works through any firewall/NAT

## Configuration

### Local Development

Default configuration in `data/local.yml`:
- Max 8 players per match (configurable)
- 2-hour session expiry
- Debug logging enabled

### Production Deployment

For production, update:
- Change admin password
- Use strong signing keys
- Enable TLS/SSL
- Configure for your cloud provider

## API Overview

### Authentication

```gdscript
# Device ID (anonymous, automatic)
await nakama.authenticate_device()

# Email + password
await nakama.authenticate_email("user@example.com", "password")

# Custom ID (link to your backend)
await nakama.authenticate_custom("user_id_123")
```

### Matchmaking

```gdscript
# Create a match
var match_info = await nakama.create_match()
print("Room code: ", match_info.label)  # Share with friends

# List available matches
var matches = await nakama.list_matches()

# Join by room code
await nakama.join_match("ABCD1234")

# Leave match
nakama.leave_match()
```

### Real-time Networking

```gdscript
# Send player transform
nakama.send_match_state(OP_CODE_TRANSFORM, {
    "position": player_position,
    "rotation": player_rotation
})

# Receive from other players
nakama.match_state_received.connect(_on_match_state)

func _on_match_state(peer_id, op_code, data):
    if op_code == OP_CODE_TRANSFORM:
        update_remote_player(peer_id, data)
```

## Integration
The system is fully integrated via the [`network_manager.gd`](../multiplayer/network_manager.gd) singleton.

1. **Authentication**: Handled automatically via Device ID on start.
2. **Persistence**: Player data and world state are synced via Nakama Match State.
3. **Relay**: High-frequency transform updates use op-codes for low-latency relay.

## Scaling

### Single Server
- **1k concurrent users**: 1x Nakama instance, small database
- **Cost**: ~$50-100/month (DigitalOcean/AWS)

### Multiple Servers
- **10k concurrent users**: 3-5x Nakama instances, load balancer
- **Cost**: ~$300-500/month

### Global Scale
- **50k+ users**: Deploy in multiple regions (US, EU, Asia)
- **Cost**: ~$1000-2000/month

See `SCALING_GUIDE.md` for details.

## Troubleshooting

### Server Won't Start

```bash
# Check logs
docker-compose logs nakama

# Recreate database
docker-compose down -v
docker-compose up
```

### Client Can't Connect

- Verify server is running: `curl http://localhost:7350`
- Check firewall allows port 7350
- Verify `NAKAMA_HOST` in client matches server IP

### High Latency

- Deploy server closer to players (regional deployments)
- Check network bandwidth
- Monitor via admin console: http://localhost:7351

## Production Deployment

### Docker (Recommended)

```bash
# Copy to production server
scp -r nakama/ user@your-server:/opt/

# Start on server
cd /opt/nakama
docker-compose up -d
```

### Cloud Providers

**AWS/GCP/DigitalOcean:**
- Use managed PostgreSQL (AWS RDS, Cloud SQL)
- Deploy Nakama as Docker containers
- Put behind load balancer for scaling

**Nakama Cloud:**
- Fully managed by Heroic Labs
- No server management needed
- Contact: https://heroiclabs.com

## Resources

- **Nakama Docs**: https://heroiclabs.com/docs
- **Godot SDK**: https://github.com/heroiclabs/nakama-godot
- **Community**: https://forum.heroiclabs.com

## Support

If you encounter issues:
1. Check the admin console for errors
2. Review server logs: `docker-compose logs nakama`
3. See migration guide: `MIGRATION_GUIDE.md`
