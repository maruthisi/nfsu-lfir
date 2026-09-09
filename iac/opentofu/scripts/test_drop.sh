#!/usr/bin/env bash
# Local self-check for drop.sh's branching (§4/§5/§6). No cloud, no network.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export SIM_STATE="$TMP"
export SIM_CONF="$TMP/config"
export SIM_TARGETS="$TMP/targets.txt"
export SIM_NO_CRON=1

cat > "$SIM_CONF" <<CFG
FILENAME="malicious_test.txt"
DURATION=4
MIN=1
MAX=2
CFG
: > "$SIM_TARGETS"                         # empty target list -> no scp attempted
bash "$HERE/setup_once.sh"                 # lays down end_epoch/next_epoch/file
[ -f "$TMP/malicious_test.txt" ] || { echo "FAIL: artifact not created"; exit 1; }

NOW=$(date +%s)

# (a) NOT due yet -> next_epoch must be untouched, no drop.
echo $(( NOW + 100 )) > "$TMP/next_epoch"
echo $(( NOW + 100 )) > "$TMP/end_epoch"
bash "$HERE/drop.sh"
[ "$(cat "$TMP/next_epoch")" = "$(( NOW + 100 ))" ] || { echo "FAIL: fired before due"; exit 1; }

# (b) DUE and inside window -> must reschedule next_epoch to a future time.
echo $(( NOW - 1 ))   > "$TMP/next_epoch"
echo $(( NOW + 100 )) > "$TMP/end_epoch"
bash "$HERE/drop.sh"
[ "$(cat "$TMP/next_epoch")" -gt "$NOW" ] || { echo "FAIL: did not reschedule"; exit 1; }

# (c) PAST deadline -> must stop (write 'stopped') and NOT reschedule.
echo $(( NOW - 1 )) > "$TMP/end_epoch"
echo "SENTINEL"      > "$TMP/next_epoch"
bash "$HERE/drop.sh"
[ -f "$TMP/stopped" ]                       || { echo "FAIL: did not stop at deadline"; exit 1; }
[ "$(cat "$TMP/next_epoch")" = "SENTINEL" ] || { echo "FAIL: sent past deadline"; exit 1; }

echo "PASS: drop.sh honors not-due / due-reschedule / deadline-stop"
