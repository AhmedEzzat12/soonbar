#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh debug
pkill -x Soonbar || true
open build/Soonbar.app
