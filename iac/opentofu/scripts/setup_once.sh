#!/usr/bin/env bash
# Runs ONCE at first boot (from cloud-init). Fixes the simulation window and the
# first randomized drop time. The harmless payload itself is shipped separately
# by cloud-init (from the repo's malicious_test.txt). No forensic logs.
set -eu

STATE="${SIM_STATE:-/opt/sim}"
CONF="${SIM_CONF:-/etc/simulation/config}"
# shellcheck source=/dev/null
. "$CONF"                       # FILENAME DURATION MIN MAX

mkdir -p "$STATE"
NOW=$(date +%s)

echo $(( NOW + DURATION ))                       > "$STATE/end_epoch"   # simulation_end_time (§4)
echo $(( NOW + MIN + RANDOM % (MAX - MIN + 1) )) > "$STATE/next_epoch"  # first drop, random (§5)

# The payload ships from the repo (malicious_test.txt). Fall back to a generated
# one only if it's somehow absent (e.g. local testing without cloud-init).
[ -f "$STATE/$FILENAME" ] || \
  printf 'Controlled Security Simulation\n\nHarmless test file.\n' > "$STATE/$FILENAME"
