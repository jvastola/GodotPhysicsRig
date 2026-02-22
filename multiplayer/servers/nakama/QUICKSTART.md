# Nakama Quick Start Guide

## Getting Started in 5 Minutes

### 1. Start Nakama Server

```bash
cd nakama
docker-compose up
```

Wait for the message: `Nakama server is ready`

### 2. Verify Server is Running

Open in browser: http://localhost:7351
- Username: `admin`
- Password: `password`

Or test with curl:
```bash
curl http://localhost:7350
```

### 3. Configure Godot Project

The NakamaManager is already created. Add it as an autoload in [`project.godot`](file:///Users/johnnyvastola/GodotPhysicsRig/project.godot):

```ini
[autoload]
NakamaManager="*res://multiplayer/nakama_manager.gd"
```

### 4. Test Authentication

In any Godot script:

```gdscript
func _ready():
    # Connect to authentication signal
    NakamaManager.authenticated.connect(_on_authenticated)
    
    # Authenticate
    NakamaManager.authenticate_device()

func _on_authenticated(session):
    print("Logged in! Session token: ", session.token)
```

## Next Steps

- See [README.md](file:///Users/johnnyvastola/GodotPhysicsRig/nakama/README.md) for full documentation
- Check [MIGRATION_GUIDE.md](file:///Users/johnnyvastola/GodotPhysicsRig/nakama/MIGRATION_GUIDE.md) for migrating from P2P

## Troubleshooting

**Server won't start:**
```bash
docker-compose down -v
docker-compose up
```

**Can't connect from Godot:**
- Check `NakamaManager.nakama_host = "localhost"`
- Verify firewall allows port 7350
