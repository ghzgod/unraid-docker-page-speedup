#!/bin/bash
# unpatch.sh: revert BOTH live patches to stock (called on plugin removal).
TAG="docker-page-speedup"
DC="/usr/local/emhttp/plugins/dynamix.docker.manager/include/DockerClient.php"; DCBAK="$DC.dpspeedup.orig"
DL="/usr/local/emhttp/plugins/dynamix.docker.manager/nchan/docker_load";        DLBAK="$DL.dpspeedup.orig"

[ -f "$DCBAK" ] && { cp -f "$DCBAK" "$DC"; rm -f "$DCBAK"; logger -t "$TAG" "restored stock DockerClient.php"; }
[ -f "$DLBAK" ] && { cp -f "$DLBAK" "$DL"; rm -f "$DLBAK"; logger -t "$TAG" "restored stock docker_load"; }
# respawn only the real php pusher, never a shell that references the path
for p in $(pgrep -f "nchan/docker_load" 2>/dev/null); do
  [ "$p" = "$$" ] && continue
  case "$(readlink -f /proc/$p/exe 2>/dev/null)" in */php*) kill "$p" 2>/dev/null;; esac
done
exit 0
