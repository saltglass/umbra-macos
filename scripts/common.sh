# Shared by build-helper.sh and sync-api.sh: finds the Umbra source folder.
# Sets SRC to UMBRA_SRC if given, else a checkout of the ref in UMBRA_VERSION.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Where Umbra is fetched from; set UMBRA_REPO to fetch it from somewhere else.
REPO="${UMBRA_REPO:-https://github.com/saltglass/umbra.git}"
if [ -n "${UMBRA_SRC:-}" ]; then
  SRC="$(cd "${UMBRA_SRC/#\~/$HOME}" && pwd)"
else
  REF="$(tr -d '[:space:]' < "$ROOT/UMBRA_VERSION")"
  SRC="$ROOT/build/umbra-src"
  if [ ! -d "$SRC/.git" ]; then
    mkdir -p "$ROOT/build"
    git clone "$REPO" "$SRC"
  fi
  git -C "$SRC" fetch --tags origin
  # Try the ref as a tag/commit, then as a branch.
  git -C "$SRC" checkout --detach -q "$REF" 2>/dev/null || git -C "$SRC" checkout --detach -q "origin/$REF"
fi
