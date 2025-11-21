# Godot Matchmaking Server

A simple, lightweight HTTP matchmaking server for Godot multiplayer games. This server provides room registration and discovery for P2P game sessions.

## Features

- ✅ Simple REST API for room management
- ✅ Automatic room expiry (default: 1 hour)
- ✅ CORS enabled for browser/Godot compatibility
- ✅ Docker support for easy deployment
- ✅ Health check endpoint
- ✅ Zero database - in-memory storage
- ✅ Ready for Oracle Cloud deployment

## Quick Start

### Option 1: Run Locally (Node.js)

```bash
# Install dependencies
npm install

# Start the server
npm start
```

The server will start on `http://localhost:8080`

### Option 2: Run with Docker

```bash
# Build and run with docker-compose
docker-compose up

# Or build and run manually
docker build -t godot-matchmaking .
docker run -p 8080:8080 godot-matchmaking
```

### Option 3: Development Mode (Auto-reload)

```bash
# Requires Node.js 18+ for --watch flag
npm run dev
```

## API Documentation

### Base URL
`http://localhost:8080` (local) or `http://your-server-ip:8080` (deployed)

### Endpoints

#### `POST /room` - Register a new room
Register a game room with the matchmaking server.

**Request:**
```json
{
  "room_code": "ABC123",
  "ip": "192.168.1.100",
  "port": 7777,
  "host_name": "Player1",
  "timestamp": 1234567890
}
```

**Response:**
```json
{
  "success": true,
  "room_code": "ABC123"
}
```

#### `GET /room/:room_code` - Lookup a room
Get connection details for a specific room.

**Response (Success):**
```json
{
  "ip": "192.168.1.100",
  "port": 7777,
  "host_name": "Player1",
  "player_count": 1,
  "timestamp": 1234567890
}
```

**Response (Not Found):**
```json
{
  "error": "Room not found"
}
```
*Status: 404*

#### `GET /rooms` - List all rooms
Get a list of all active rooms.

**Response:**
```json
[
  {
    "room_code": "ABC123",
    "ip": "192.168.1.100",
    "port": 7777,
    "host_name": "Player1",
    "player_count": 1,
    "timestamp": 1234567890
  }
]
```

#### `DELETE /room/:room_code` - Unregister a room
Remove a room from the matchmaking server.

**Response:**
```json
{
  "success": true
}
```

#### `GET /health` - Health check
Check if the server is running.

**Response:**
```json
{
  "status": "ok",
  "uptime": 3600,
  "rooms": 5,
  "timestamp": 1234567890
}
```

## Configuration

Create a `.env` file based on `.env.example`:

```bash
PORT=8080
ROOM_EXPIRY_SECONDS=3600
```

**Environment Variables:**
- `PORT` - Server port (default: 8080)
- `ROOM_EXPIRY_SECONDS` - Time in seconds before rooms are automatically removed (default: 3600)

## Godot Integration

Your Godot project already has a matchmaking client at `multiplayer/matchmaking_server.gd`. To use this server:

1. Start the matchmaking server (locally or deployed)
2. In Godot, the client defaults to `http://localhost:8080`
3. To use a deployed server, set the URL:

```gdscript
# In your Godot script
var matchmaking = get_node("/root/MatchmakingServer")
matchmaking.matchmaking_url = "http://your-server-ip:8080"
```

The existing Godot client already implements all the necessary API calls.

## Testing

### Test with cURL

```bash
# Register a room
curl -X POST http://localhost:8080/room \
  -H "Content-Type: application/json" \
  -d '{"room_code":"TEST123","ip":"127.0.0.1","port":7777,"host_name":"TestHost"}'

# Lookup the room
curl http://localhost:8080/room/TEST123

# List all rooms
curl http://localhost:8080/rooms

# Health check
curl http://localhost:8080/health

# Delete room
curl -X DELETE http://localhost:8080/room/TEST123
```

## Oracle Cloud Deployment

See [ORACLE_CLOUD_DEPLOY.md](ORACLE_CLOUD_DEPLOY.md) for detailed step-by-step instructions on deploying to Oracle Cloud.

### Quick Deployment Overview

1. **Create an Oracle Cloud Compute Instance**
   - Ubuntu or Oracle Linux
   - Open port 8080 in firewall

2. **Install Docker** on the instance

3. **Deploy the server:**
   ```bash
   # On your Oracle Cloud instance
   git clone <your-repo>
   cd godotmatchmaking
   docker-compose up -d
   ```

4. **Configure Godot client** with your instance's public IP

## Production Considerations

### Security
- Consider adding authentication for room registration
- Use HTTPS with a reverse proxy (nginx/Apache)
- Implement rate limiting to prevent abuse
- Restrict CORS to specific origins in production

### Scalability
- Current implementation uses in-memory storage (rooms reset on restart)
- For production, consider adding Redis or database backend
- Use a process manager like PM2 for auto-restart
- Put behind a load balancer for multiple instances

### Monitoring
- Check `/health` endpoint for uptime monitoring
- Monitor server logs for errors
- Set up alerts for server downtime

## License

MIT
