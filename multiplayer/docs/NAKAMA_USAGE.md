# Nakama Integration Guide

## Quick Start

### 1. Make Sure Server is Running

```bash
cd nakama
docker-compose up -d
```

Verify: http://localhost:7351 (admin/password)

### 2. The Integration is Ready!

NakamaManager is already added to your project as an autoload. It will automatically:
- Authenticate when the game starts
- Connect WebSocket
- Be ready for matchmaking

### 3. Test the Integration

Create a test scene (`res://multiplayer/client/scenes/nakama_test.tscn`) with `nakama_test.gd` attached:

**Or add to any existing script:**
```gdscript
func _ready():
    # Connect signals
    NakamaManager.authenticated.connect(_on_authenticated)
    NakamaManager.match_created.connect(_on_match_created)
  
func _on_authenticated(session):
    print("Logged in! User ID: ", session.user_id)
    
func _on_match_created(match_id, label):
    print("Room created: ", label)
```

## Using Nakama for Multiplayer

### Create a Match (Host)

```gdscript
func host_game():
    # Wait for authentication first
    if not NakamaManager.is_authenticated:
        await NakamaManager.authenticated
    
    # Create match
    NakamaManager.match_created.connect(_on_match_created)
    NakamaManager.create_match()

func _on_match_created(match_id, label):
    print("Share this code with friends: ", label)
    # match_id is the actual ID to join
```

### Join a Match (Client)

```gdscript
func join_game(match_id: String):
    if not NakamaManager.is_authenticated:
        await NakamaManager.authenticated
    
    NakamaManager.match_joined.connect(_on_match_joined)
    NakamaManager.join_match(match_id)

func _on_match_joined(match_id):
    print("Joined match: ", match_id)
```

### Send Player Transform

```gdscript
func _physics_process(_delta):
    if NakamaManager.current_match_id.is_empty():
        return
    
    # Send transform to other players
    NakamaManager.send_match_state(
        NakamaManager.MatchOpCode.PLAYER_TRANSFORM,
        {
            "position": {
                "x": position.x,
                "y": position.y,
                "z": position.z
            },
            "rotation": {
                "x": rotation.x,
                "y": rotation.y,
                "z": rotation.z
            }
        }
    )
```

### Receive Player Transform

```gdscript
func _ready():
    NakamaManager.match_state_received.connect(_on_match_state)

func _on_match_state(peer_id, op_code, data):
    if op_code == NakamaManager.MatchOpCode.PLAYER_TRANSFORM:
        var pos = Vector3(
            data.position.x,
            data.position.y,
            data.position.z
        )
        var rot = Vector3(
            data.rotation.x,
            data.rotation.y,
            data.rotation.z
        )
        update_remote_player(peer_id, pos, rot)
```

## Available Op Codes

```gdscript
NakamaManager.MatchOpCode.PLAYER_TRANSFORM  # Player pos/rot
NakamaManager.MatchOpCode.GRABBABLE_GRAB    # Object grabbed
NakamaManager.MatchOpCode.GRABBABLE_RELEASE # Object released
NakamaManager.MatchOpCode.GRABBABLE_UPDATE  # Grabbed object update
NakamaManager.MatchOpCode.VOXEL_PLACE       # Voxel placed
NakamaManager.MatchOpCode.VOXEL_REMOVE      # Voxel removed
NakamaManager.MatchOpCode.VOICE_DATA        # Voice chat data
```

## Switching Between P2P and Nakama

In `network_manager.gd`:

```gdscript
# Use P2P (current system)
NetworkManager.use_nakama = false

# Use Nakama (scalable relay)
NetworkManager.use_nakama = true
```

## Signals Reference

```gdscript
# Authentication
NakamaManager.authenticated(session)
NakamaManager.authentication_failed(error)

# Connection
NakamaManager.connection_restored()
NakamaManager.connection_lost()

# Matchmaking
NakamaManager.match_created(match_id, label)
NakamaManager.match_joined(match_id)
NakamaManager.match_left()
NakamaManager.match_error(error)

# Match events
NakamaManager.match_presence(joins, leaves)
NakamaManager.match_state_received(peer_id, op_code, data)
```

## Testing Locally

1. **Start Nakama server**: `cd nakama && docker-compose up`
2. **Run two game instances**
3. **Instance 1**: Create match (press H in test scene)
4. **Instance 2**: Join match with the ID

## Production Deployment

When ready for production:

1. Deploy Nakama to cloud (see `nakama/ORACLE_CLOUD_DEPLOY.md`)
2. Update `nakama_manager.gd`:
   ```gdscript
   var nakama_host: String = "your-server-ip"
   var nakama_use_ssl: bool = true  # Enable HTTPS
   ```
3. Change all default passwords
4. Enable TLS/SSL

## Troubleshooting

**"Socket not connected"**
- Wait for `connection_restored` signal
- Check Nakama server is running

**"Must authenticate first"**
- Wait for `authenticated` signal before creating matches

**Authentication fails**
- Check Nakama server: `docker ps`
- Check logs: `docker logs nakama`
- Verify ports 7350/7351 are accessible

## Next Steps

1. Test authentication (should auto-run on _ready)
2. Create a match from one instance
3. Join from another instance  
4. Send/receive match state
5. Integrate with existing multiplayer code

See also:
- [`nakama/README.md`](file:///Users/johnnyvastola/GodotPhysicsRig/nakama/README.md) - Full Nakama docs
- [`nakama_test.gd`](file:///Users/johnnyvastola/GodotPhysicsRig/multiplayer/nakama_test.gd) - Test scene example
