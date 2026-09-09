#!/usr/bin/env bash
# Invoked every minute by cron. Decides whether a randomized drop is due, sends
# the file to all users via scp, and enforces the hard 15-min deadline.
# Paths are overridable (SIM_*) purely so test_drop.sh can exercise the logic.
set -u

CONF="${SIM_CONF:-/etc/simulation/config}"
STATE="${SIM_STATE:-/opt/sim}"
TARGETS="${SIM_TARGETS:-/etc/simulation/targets.txt}"
# shellcheck source=/dev/null
. "$CONF"                       # FILENAME MIN MAX

NOW=$(date +%s)
END=$(cat "$STATE/end_epoch")

# Hard deadline (§4/§6): stop, remove our own cron entry, and never send again.
if [ "$NOW" -ge "$END" ]; then
  if [ -n "${SIM_NO_CRON:-}" ]; then
    : > "$STATE/stopped"        # test hook: don't touch a real crontab
  else
    crontab -l 2>/dev/null | grep -v '/opt/sim/drop.sh' | crontab - 2>/dev/null || true
  fi
  exit 0
fi

# Not yet due for the next randomized drop -> do nothing this minute.
if [ "$NOW" -lt "$(cat "$STATE/next_epoch")" ]; then
  exit 0
fi

# Due -> copy the file to every mirror (shared-key auth, no password).
while read -r ip; do
  [ -n "$ip" ] || continue
  scp -q -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    "$STATE/$FILENAME" "analyst@$ip:$DEST/" 2>/dev/null || true
done < "$TARGETS"

# Re-roll the next drop 180-240s ahead (§5).
echo $(( NOW + MIN + RANDOM % (MAX - MIN + 1) )) > "$STATE/next_epoch"
