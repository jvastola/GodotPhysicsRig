#!/bin/bash
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "Run as root (sudo) to modify firewall rules"
  exit 1
fi

# Insert ACCEPT rule for 8080 before REJECT (if present), avoid duplicates, handle multiple REJECT rules
# Check if ACCEPT rule for port 8080 already exists
if iptables -C INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null; then
  echo "ACCEPT rule for TCP 8080 already exists, skipping insertion."
else
  # Find all line numbers of REJECT rules with 'icmp-host-prohibited'
  REJECT_LINES=($(iptables -L INPUT --line-numbers -n | awk '/REJECT/ && /icmp-host-prohibited/{print $1}'))
  if [[ ${#REJECT_LINES[@]} -eq 0 ]]; then
    # No REJECT rule found, insert at top
    if ! iptables -I INPUT -p tcp --dport 8080 -j ACCEPT; then
      echo "Failed to insert ACCEPT rule for TCP 8080" >&2
      exit 2
    fi
  else
    # Insert before the first REJECT rule
    FIRST_REJECT_LINE=${REJECT_LINES[0]}
    if ! iptables -I INPUT ${FIRST_REJECT_LINE} -p tcp --dport 8080 -j ACCEPT; then
      echo "Failed to insert ACCEPT rule for TCP 8080 before REJECT rule" >&2
      exit 2
    fi
  fi
fi

netfilter-persistent save || true
echo "Added iptables rule to accept TCP 8080 (persisted)"
