#!/usr/bin/env bash
# Copies Umbra's API description into the Swift package and records which
# Umbra commit it came from, so the generated client can be traced to it.
set -euo pipefail
. "$(dirname "$0")/common.sh"
DEST="$ROOT/UmbraKit/Sources/UmbraAPI"
cp "$SRC/api/openapi.yaml" "$DEST/openapi.yaml"
git -C "$SRC" rev-parse HEAD > "$DEST/openapi.ref"
echo "API copied from $SRC at $(cat "$DEST/openapi.ref")"
