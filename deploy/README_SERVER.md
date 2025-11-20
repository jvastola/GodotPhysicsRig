# Godot Headless Matchmaking Server - Deployment Guide

This document explains how to run the headless Godot matchmaking server on a Linux VM and make it reachable externally.

Prerequisites
- Godot Engine headless binary installed at `/usr/local/bin/godot`.
- Project deployed to `/home/ubuntu/GodotPhysicsRig`.
- VM with public IP assigned and firewall access.

Start server (manual test)
1. Stop any running Godot:
   pkill godot || true
2. Start server and log:
   nohup /usr/local/bin/godot --verbose --headless --script ~/GodotPhysicsRig/server_standalone.gd > ~/server.log 2>&1 &
3. Inspect logs:
   tail -n 200 ~/server.log

Make server persistent (systemd)
1. Copy service (requires root):
   sudo cp deploy/godot-matchmaking.service /etc/systemd/system/godot-matchmaking.service
2. Reload and enable:
   sudo systemctl daemon-reload
   sudo systemctl enable --now godot-matchmaking.service
3. Ensure the environment file points to the script (used by the unit). If `/etc/default/godot-matchmaking` is not present, create it:
   sudo bash -c 'echo "GODOT_PROJECT_PATH=/home/ubuntu/GodotPhysicsRig/server_standalone.gd" > /etc/default/godot-matchmaking'
   sudo systemctl restart godot-matchmaking.service
3. Check logs:
   sudo journalctl -u godot-matchmaking.service -f

Firewall & Cloud Network
1. Ensure VM is listening:
   ss -tulnp | grep 8080
2. Add host firewall accept rule (iptables):
   sudo iptables -I INPUT 5 -p tcp --dport 8080 -j ACCEPT
   sudo netfilter-persistent save
3. Ensure OCI security lists / network security group allow TCP port 8080 ingress for the required source IPs.

Debugging
- Use `tcpdump -n -i any port 8080` (root) to see raw packets arriving.
- Check system logs or `~/server.log` for GDScript errors.
- Use `ss -tulnp` to confirm service listening on host.

Security
- Prefer to allow specific IP ranges only (restrict to your app servers), not 0.0.0.0/0.
- Consider a reverse proxy (Nginx) with TLS and basic auth for production.
