# Nakama Lua Update Guide

This document describes how to update the Nakama Lua runtime modules on the Oracle Cloud server.

## Prerequisites

1.  **SSH Key**: You must have the private SSH key available at `/Users/jv/Documents/privatessh-key-2025-11-20.key`.
2.  **Server IP**: The public IP of the Nakama server is `158.101.21.99`.

## Update Procedure

### 1. Prepare the Lua Script
Ensure your local Changes are reflected in `multiplayer/servers/nakama/livekit_rpc.oracle.lua`.

> [!IMPORTANT]
> Do not use `os.getenv` in Nakama Lua scripts as it is not supported and will cause a runtime error. Use hardcoded defaults or Nakama-specific configuration methods.

### 2. Upload the Script
Use `scp` to upload the file to a temporary location on the server (due to permission restrictions on the target directory):

```bash
scp -i "/Users/jv/Documents/privatessh-key-2025-11-20.key" \
  multiplayer/servers/nakama/livekit_rpc.oracle.lua \
  ubuntu@158.101.21.99:/tmp/livekit_rpc.lua
```

### 3. Move and Apply Permissions
SSH into the server to move the file to the Nakama modules directory and set correct ownership:

```bash
ssh -i "/Users/jv/Documents/privatessh-key-2025-11-20.key" ubuntu@158.101.21.99 \
  "sudo mv /tmp/livekit_rpc.lua /home/ubuntu/GodotPhysicsRig/nakama/data/modules/livekit_rpc.lua && \
   sudo chown ubuntu:ubuntu /home/ubuntu/GodotPhysicsRig/nakama/data/modules/livekit_rpc.lua"
```

### 4. Restart Nakama
Restart the Nakama container to load the new Lua module:

```bash
ssh -i "/Users/jv/Documents/privatessh-key-2025-11-20.key" ubuntu@158.101.21.99 \
  "cd ~/GodotPhysicsRig/nakama && docker-compose restart nakama"
```

### 5. Verify Successful Startup
Check the logs to ensure no Lua errors occurred:

```bash
ssh -i "/Users/jv/Documents/privatessh-key-2025-11-20.key" ubuntu@158.101.21.99 \
  "cd ~/GodotPhysicsRig/nakama && docker-compose logs --tail 50 nakama"
```

Look for the message: `{"level":"info",...,"msg":"Startup done"}`.

## Troubleshooting

- **Permission Denied**: If you get a permission error during SCP, ensure you are uploading to `/tmp/` first and then moving with `sudo`.
- **Lua Runtime Error**: Check the logs for `attempt to call a non-function object` or similar errors. This usually means a function or global (like `os.getenv`) is missing from the environment.
