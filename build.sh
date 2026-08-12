#!/bin/bash
# Build a self-contained, SHAREABLE docker.page.speedup.plg from src/.
# Embeds every src file inline (CDATA) plus install/remove scripts.
# Contains NO secrets and needs no configuration. Safe to publish.
#
# Usage: ./build.sh [version]   (default version below)
set -euo pipefail

cd "$(dirname "$0")"
VERSION="${1:-2026.08.12}"
NAME="docker.page.speedup"
SRC="src/usr/local/emhttp/plugins/$NAME"
OUT="$NAME.plg"
PLUGIN_URL="https://raw.githubusercontent.com/ghzgod/unraid-docker-page-speedup/main/docker.page.speedup.plg"
SUPPORT_URL="https://github.com/ghzgod/unraid-docker-page-speedup"

# --- payload files installed to /usr/local/emhttp/plugins/<name>/ ----------
FILES=(dockerclient_speedup.py apply.sh unpatch.sh default.cfg DockerPageSpeedup.page README.md)

# guard: CDATA cannot contain ]]>
for f in "${FILES[@]}"; do
  if grep -q ']]>' "$SRC/$f"; then echo "ERROR: $f contains ]]> (breaks CDATA)" >&2; exit 1; fi
done

emit_payload() {
  local f="$1"
  printf '<FILE Name="/usr/local/emhttp/plugins/%s/%s">\n<INLINE>\n<![CDATA[\n' "$NAME" "$f"
  cat "$SRC/$f"
  printf ']]>\n</INLINE>\n</FILE>\n\n'
}

{
cat <<XMLHEAD
<?xml version='1.0' standalone='yes'?>
<!DOCTYPE PLUGIN [
<!ENTITY name    "$NAME">
<!ENTITY author  "ghzgod">
<!ENTITY version "$VERSION">
<!ENTITY launch  "Settings/DockerPageSpeedup">
<!ENTITY plugin  "$PLUGIN_URL">
<!ENTITY support "$SUPPORT_URL">
]>
<PLUGIN name="&name;" author="&author;" version="&version;" launch="&launch;" pluginURL="&plugin;" min="6.12" icon="bolt" support="&support;">

<CHANGES>
##$VERSION
- Renamed to Unraid Docker Page Speedup, in the plugin, the README and the App
  Store listing. Same plugin, same settings, nothing else changes.

##2026.07.31
- Fix: on some systems the boot-time run patched DockerClient.php, failed its own
  php -l verification before the rest of userspace was up, and rolled back to
  stock, leaving the page-load speedup silently off until something re-ran it. If
  the cache is enabled but not present at the end of a run, it now retries once
  after the system settles.
- Added the Community Applications submission metadata (ca_profile.xml, plugin
  wrapper) and an MIT LICENSE.
- New: Settings page (Settings -> Utilities -> Docker Page Speedup, or click the bolt icon)
  to toggle the page-load speedup and set the Docker stats refresh interval.
- New: configurable Docker stats refresh (default 5s) throttles nchan/docker_load, cutting
  CPU/GPU load from the stock 1s live-stats repaint while the Docker page is open.
- Page-load speedup measured ~9x cold / ~56x warm on a server with well over 100 containers.
- Fix: Plugins-page description renders at normal size. The README is a bold title with a
  plain-text body (the webGUI styles headings and body bold at 1.3rem, i.e. oversized).
- Config-driven, idempotent, anchor-guarded, php -l verified with auto-rollback; both
  patches fully reverted on uninstall.
</CHANGES>

<FILE Run="/bin/bash">
<INLINE>
<![CDATA[
mkdir -p /usr/local/emhttp/plugins/$NAME
]]>
</INLINE>
</FILE>

XMLHEAD

for f in "${FILES[@]}"; do emit_payload "$f"; done

cat <<'POSTINSTALL'
<FILE Run="/bin/bash">
<INLINE>
<![CDATA[
# seed persistent config on flash (preserve user settings across updates)
mkdir -p /boot/config/plugins/docker.page.speedup
[ -f /boot/config/plugins/docker.page.speedup/docker.page.speedup.cfg ] || \
  cp /usr/local/emhttp/plugins/docker.page.speedup/default.cfg \
     /boot/config/plugins/docker.page.speedup/docker.page.speedup.cfg
chmod +x /usr/local/emhttp/plugins/docker.page.speedup/apply.sh \
         /usr/local/emhttp/plugins/docker.page.speedup/unpatch.sh
# apply per the saved config
bash /usr/local/emhttp/plugins/docker.page.speedup/apply.sh
echo "----------------------------------------------------"
echo " Unraid Docker Page Speedup installed."
echo " Settings -> Utilities -> Unraid Docker Page Speedup (or the bolt icon)."
echo " Re-applied on every boot. syslog tag: docker-page-speedup"
echo "----------------------------------------------------"
]]>
</INLINE>
</FILE>

<FILE Run="/bin/bash" Method="remove">
<INLINE>
<![CDATA[
bash /usr/local/emhttp/plugins/docker.page.speedup/unpatch.sh 2>/dev/null
rm -rf /usr/local/emhttp/plugins/docker.page.speedup
rm -rf /boot/config/plugins/docker.page.speedup
]]>
</INLINE>
</FILE>

</PLUGIN>
POSTINSTALL
} > "$OUT"

# Hard gate, not a promise: this artifact is published to a public repo, so it
# must never carry a credential or anything identifying the machine it was built on.
if grep -qaE 'gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{20,}|BEGIN [A-Z ]*PRIVATE KEY|ssh-rsa' "$OUT"; then
  echo "ERROR: $OUT contains something credential shaped. Refusing to ship it." >&2
  rm -f "$OUT"; exit 1
fi
if grep -qaE '(\b(192\.168|10\.)[0-9.]+)|/Users/|[a-z0-9-]+\.ts\.net' "$OUT"; then
  echo "ERROR: $OUT contains a private IP, a local path or a Tailscale name. Refusing to ship it." >&2
  rm -f "$OUT"; exit 1
fi

echo "Built $OUT ($VERSION), secret-free (verified), ${#FILES[@]} files embedded."
