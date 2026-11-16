#!/usr/bin/env bash
# Builds Umbra's server program for the Mac into build/helper/umbra.
# Uses Umbra's own `just build-mac` when it has one, else `just build`.
set -euo pipefail
. "$(dirname "$0")/common.sh"
cd "$SRC"
if just --summary | tr ' ' '\n' | grep -qx build-mac; then
  just build-mac
  OUT="bin/umbra-darwin-arm64"
else
  just build
  OUT="bin/umbra"
fi
mkdir -p "$ROOT/build/helper"
cp -f "$SRC/$OUT" "$ROOT/build/helper/umbra"
chmod +x "$ROOT/build/helper/umbra"
echo "Helper built: $ROOT/build/helper/umbra"
