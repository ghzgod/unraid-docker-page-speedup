#!/bin/bash
# docker.page.speedup — apply the DockerClient.php performance patch.
#
# Runs on plugin install AND on every boot: Unraid re-runs `plugin install` for
# every .plg at boot (see /etc/rc.d/rc.local), and the webGUI lives in RAM so it
# is stock again after each boot — we re-apply here. Idempotent, syntax-verified,
# auto-rollback on failure.
TAG="docker-page-speedup"
DIR="/usr/local/emhttp/plugins/docker.page.speedup"
TARGET="/usr/local/emhttp/plugins/dynamix.docker.manager/include/DockerClient.php"
BACKUP="$TARGET.dpspeedup.orig"
VER=$(grep -oP 'version="\K[^"]+' /etc/unraid-version 2>/dev/null)

[ -f "$TARGET" ] || { logger -t "$TAG" "target not found, skipping"; exit 0; }

# Idempotent: already patched this boot?
if grep -q 'templatesCache' "$TARGET"; then
  logger -t "$TAG" "already patched (Unraid $VER)"; exit 0
fi

# Keep a copy of the current (stock) file so removal / rollback can restore it.
cp -f "$TARGET" "$BACKUP"

OUT=$(python3 "$DIR/dockerclient_speedup.py" "$TARGET" 2>&1); RC=$?
if [ "$RC" -ne 0 ]; then
  # Anchors did not match — a different Unraid build. Leave the stock file as-is.
  logger -t "$TAG" "not applied on Unraid $VER (${OUT})"
  rm -f "$BACKUP"
  exit 0
fi

# Verify PHP still parses; roll back to stock on any syntax error.
if ! php -l "$TARGET" >/dev/null 2>&1; then
  logger -t "$TAG" "php -l FAILED after patch — rolling back to stock"
  cp -f "$BACKUP" "$TARGET"
  rm -f "$BACKUP"
  exit 1
fi

logger -t "$TAG" "applied Docker-page speedup on Unraid $VER"
exit 0
