#!/usr/bin/env bash
# Runs every minute on a SOURCE. Sends the file to every mirror at a randomized
# interval within a fixed window, then removes its own cron entry at the deadline.
# Paths overridable via SIM_* for local testing.
set -u
CONF="${SIM_CONF:-/etc/simulation/config}"
STATE="${SIM_STATE:-/opt/sim}"
TARGETS="${SIM_TARGETS:-/etc/simulation/targets.txt}"
KEY="${SIM_KEY:-/opt/sim/sim_key}"
# shellcheck source=/dev/null
. "$CONF"                                   # FILENAME MIN MAX DEST

NOW=$(date +%s)
END=$(cat "$STATE/end_epoch")

# Hard deadline: stop and remove our own cron entry.
if [ "$NOW" -ge "$END" ]; then
  crontab -l 2>/dev/null | grep -v '/opt/sim/drop.sh' | crontab - 2>/dev/null || true
  exit 0
fi

# Not yet due for the next randomized drop.
[ "$NOW" -lt "$(cat "$STATE/next_epoch")" ] && exit 0

# Due: scp the file to every mirror (as analyst, using the shared key).
while read -r ip; do
  [ -n "$ip" ] || continue
  scp -q -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    "$DEST/$FILENAME" "analyst@$ip:$DEST/" 2>/dev/null || true
done < "$TARGETS"

# Re-roll the next drop 180-240s ahead.
echo $(( NOW + MIN + RANDOM % (MAX - MIN + 1) )) > "$STATE/next_epoch"
