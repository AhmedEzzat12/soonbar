#!/usr/bin/env bash
# Quits any running Soonbar and waits for it to exit. Without the wait, `open` hands the
# launch to the still-quitting instance (LaunchServices error -600) and nothing starts.
set -euo pipefail
pkill -x Soonbar || exit 0
for _ in $(seq 50); do
  pgrep -x Soonbar >/dev/null || exit 0
  sleep 0.1
done
echo "Soonbar did not quit within 5 s" >&2
exit 1
