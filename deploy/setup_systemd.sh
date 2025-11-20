#!/bin/bash
set -euo pipefail

# Script: deploy/setup_systemd.sh
# Purpose: Install and enable the godot-matchmaking systemd unit

SERVICE_PATH="/etc/systemd/system/godot-matchmaking.service"

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root (sudo)"
  exit 1
fi

cp ./deploy/godot-matchmaking.service ${SERVICE_PATH}
systemctl daemon-reload
systemctl enable --now godot-matchmaking.service
systemctl status godot-matchmaking.service --no-pager

echo "Systemd service installed and started. Check logs with: journalctl -u godot-matchmaking.service -f"
