#!/usr/bin/env bash
# Release build copied to ~/Applications (a stable path for launch at login).
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh release
pkill -x Soonbar || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Soonbar.app"
cp -R build/Soonbar.app "$HOME/Applications/"
open "$HOME/Applications/Soonbar.app"
