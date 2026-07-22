#!/bin/bash
# docker.page.speedup — revert the live patch (called on plugin removal).
TAG="docker-page-speedup"
TARGET="/usr/local/emhttp/plugins/dynamix.docker.manager/include/DockerClient.php"
BACKUP="$TARGET.dpspeedup.orig"

if [ -f "$BACKUP" ]; then
  cp -f "$BACKUP" "$TARGET"
  rm -f "$BACKUP"
  logger -t "$TAG" "restored stock DockerClient.php from backup"
else
  logger -t "$TAG" "no backup present; the stock file is restored automatically on next reboot"
fi
exit 0
