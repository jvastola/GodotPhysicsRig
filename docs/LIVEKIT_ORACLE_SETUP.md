# LiveKit Server - Oracle Cloud Setup

## Server Details
- **Provider**: Oracle Cloud
- **Public IP**: `158.101.21.99`
- **Region**: (Same as Nakama instance)
- **OS**: Ubuntu (Oracle Linux compatible)
- **SSH Key**: `C:\Users\johnn\Downloads\privatessh-key-2025-11-20.key`

## Ports (Security List)
These ports must be open in the **Oracle Cloud Default Security List**:

| Port | Protocol | Service | Description |
|------|----------|---------|-------------|
| 7880 | TCP | API/Signal | Main entry point for clients |
| 7881 | TCP | HTTP/WebRTC | TCP fallback for WebRTC |
| 7882 | UDP | WebRTC | Main media transport |
| 50000-60000 | UDP | ICE | (Recommended) RTP range |

## Server Configuration
Located at `~/GodotPhysicsRig/livekit_server/` on the remote machine.

### `livekit.yaml`
```yaml
port: 7880
bind_addresses:
    - ""
rtc:
    udp_port: 7882
    tcp_port: 7881
    # Node IP is set via command line flag --node-ip
redis:
    address: localhost:6379
keys:
    devkey: secret12345678901234567890123456 # Secure implementation key
logging:
    json: false
    level: info
```

### `docker-compose.yml`
```yaml
version: "3"
services:
  livekit:
    image: livekit/livekit-server:latest
    command: --config /etc/livekit.yaml --node-ip 158.101.21.99
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./livekit.yaml:/etc/livekit.yaml
    depends_on:
      - redis

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    network_mode: host
```

## Management Commands

### Connect to Server
```powershell
ssh -i "C:\Users\johnn\Downloads\privatessh-key-2025-11-20.key" ubuntu@158.101.21.99
```

### View Logs
```bash
cd ~/GodotPhysicsRig/livekit_server
docker-compose logs -f
```

### Restart Server
```bash
cd ~/GodotPhysicsRig/livekit_server
docker-compose down
docker-compose up -d
```

## Godot Client Configuration

### `src/ui/livekit/livekit_utils.gd`
Ensure the secret matches the server:
```gdscript
const DEFAULT_API_SECRET = "secret12345678901234567890123456"
```

### `src/ui/livekit/components/connection_panel.gd`
Default URL:
```gdscript
server_entry.text = "ws://158.101.21.99:7880"
```
