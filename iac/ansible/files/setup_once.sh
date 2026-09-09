#!/usr/bin/env bash
# Runs once when the sender is deployed: fixes the simulation window and the first
# randomized drop time. The payload is placed by Ansible; this is a safety net.
set -eu
STATE="${SIM_STATE:-/opt/sim}"
CONF="${SIM_CONF:-/etc/simulation/config}"
# shellcheck source=/dev/null
. "$CONF"
mkdir -p "$STATE" "$DEST"
NOW=$(date +%s)
echo $(( NOW + DURATION ))                       > "$STATE/end_epoch"
echo $(( NOW + MIN + RANDOM % (MAX - MIN + 1) )) > "$STATE/next_epoch"
[ -f "$DEST/$FILENAME" ] || \
  printf 'Controlled Security Simulation\n\nHarmless test file.\n' > "$DEST/$FILENAME"
