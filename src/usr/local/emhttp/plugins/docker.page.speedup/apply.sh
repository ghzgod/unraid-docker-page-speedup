#!/bin/bash
# apply.sh — config-driven application of the two Docker-page optimizations.
#
# Invoked:
#   * at plugin install / every boot  (via the .plg <FILE Run>)
#   * after Settings -> Apply          (via the page's #command)
# Reads /boot/config/plugins/docker.page.speedup/docker.page.speedup.cfg (which
# update.php has already written before calling us) and makes the live webGUI
# match it. Idempotent, php -l verified with auto-rollback, fully reversible.
TAG="docker-page-speedup"
DIR="/usr/local/emhttp/plugins/docker.page.speedup"
CFG="/boot/config/plugins/docker.page.speedup/docker.page.speedup.cfg"
DC="/usr/local/emhttp/plugins/dynamix.docker.manager/include/DockerClient.php"
DCBAK="$DC.dpspeedup.orig"
DL="/usr/local/emhttp/plugins/dynamix.docker.manager/nchan/docker_load"
DLBAK="$DL.dpspeedup.orig"

# --- read config (fall back to sane defaults) ------------------------------
TEMPLATE_CACHE=1
STATS_INTERVAL=5
if [ -f "$CFG" ]; then
  v=$(grep -E '^TEMPLATE_CACHE=' "$CFG" | head -1 | cut -d'"' -f2); [ -n "$v" ] && TEMPLATE_CACHE="$v"
  v=$(grep -E '^STATS_INTERVAL='  "$CFG" | head -1 | cut -d'"' -f2); [ -n "$v" ] && STATS_INTERVAL="$v"
fi
case "$STATS_INTERVAL" in ''|*[!0-9]*) STATS_INTERVAL=5;; esac
[ "$STATS_INTERVAL" -lt 1 ]  && STATS_INTERVAL=1
[ "$STATS_INTERVAL" -gt 60 ] && STATS_INTERVAL=60

# --- 1) DockerClient.php template-read caching (page-load speedup) ----------
if [ -f "$DC" ]; then
  if [ "$TEMPLATE_CACHE" = "1" ]; then
    if ! grep -q 'templatesCache' "$DC"; then
      cp -f "$DC" "$DCBAK"
      if python3 "$DIR/dockerclient_speedup.py" "$DC" >/dev/null 2>&1 && php -l "$DC" >/dev/null 2>&1; then
        logger -t "$TAG" "template cache ON (Unraid $(grep -oP 'version="\K[^"]+' /etc/unraid-version 2>/dev/null))"
      else
        cp -f "$DCBAK" "$DC"; rm -f "$DCBAK"
        logger -t "$TAG" "template cache patch failed php -l — rolled back to stock"
      fi
    fi
  else
    if grep -q 'templatesCache' "$DC" && [ -f "$DCBAK" ]; then
      cp -f "$DCBAK" "$DC"; rm -f "$DCBAK"
      logger -t "$TAG" "template cache OFF — restored stock DockerClient.php"
    fi
  fi
fi

# --- 2) docker_load live-stats refresh interval (CPU/GPU load) --------------
# The stock nchan pusher runs `docker stats` on every container every 1s while
# the Docker page is open, forcing a full table repaint each second (heavy on
# CPU and on the browser GPU). We reset to stock, then set the chosen interval.
if [ -f "$DL" ]; then
  [ -f "$DLBAK" ] || cp -f "$DL" "$DLBAK"   # capture pristine stock once (boot = stock)
  cp -f "$DLBAK" "$DL"                        # always start from stock so it's re-configurable
  if [ "$STATS_INTERVAL" -gt 1 ]; then
    sed -i "s/sleep(1);/sleep(${STATS_INTERVAL});/" "$DL"
    logger -t "$TAG" "docker stats refresh = ${STATS_INTERVAL}s"
  else
    logger -t "$TAG" "docker stats refresh = 1s (stock)"
  fi
  # respawn the running pusher (if the page is open) so the change takes effect now.
  # Only kill the real pusher — a php process running the script — never a shell
  # that merely references the path (matched by cmdline). Check the actual exe.
  for p in $(pgrep -f "nchan/docker_load" 2>/dev/null); do
    [ "$p" = "$$" ] && continue
    case "$(readlink -f /proc/$p/exe 2>/dev/null)" in */php*) kill "$p" 2>/dev/null;; esac
  done
fi
exit 0
