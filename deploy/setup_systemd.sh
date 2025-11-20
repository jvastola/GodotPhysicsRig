#!/bin/bash
set -euo pipefail

# Script: deploy/setup_systemd.sh
# Purpose: Install and enable the godot-matchmaking systemd unit

SERVICE_PATH="/etc/systemd/system/godot-matchmaking.service"
ENV_FILE="/etc/default/godot-matchmaking"
GODOT_SCRIPT_PATH="/home/ubuntu/GodotPhysicsRig/server_standalone.gd"

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root (sudo)"
  exit 1
fi

cp ./deploy/godot-matchmaking.service ${SERVICE_PATH}
# Create environment file to point the service to the script if it does not exist or is empty
if [[ ! -f "${ENV_FILE}" || -z "$(cat ${ENV_FILE})" ]]; then
  echo "GODOT_PROJECT_PATH=${GODOT_SCRIPT_PATH}" > ${ENV_FILE}
  echo "Wrote ${ENV_FILE} -> GODOT_PROJECT_PATH=${GODOT_SCRIPT_PATH}"
else
  echo "Environment file ${ENV_FILE} already exists (leave unchanged)."
fi
systemctl daemon-reload
systemctl enable --now godot-matchmaking.service
systemctl status godot-matchmaking.service --no-pager

echo "Systemd service installed and started. Check logs with: journalctl -u godot-matchmaking.service -f"
