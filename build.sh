#!/bin/bash
# Build a self-contained, SHAREABLE docker.page.speedup.plg from src/.
# Embeds every src file inline (CDATA) plus install/remove scripts.
# Contains NO secrets and needs no configuration. Safe to publish.
#
# Usage: ./build.sh [version]   (default version below)
set -euo pipefail

cd "$(dirname "$0")"
VERSION="${1:-2026.07.21}"
NAME="docker.page.speedup"
SRC="src/usr/local/emhttp/plugins/$NAME"
OUT="$NAME.plg"
PLUGIN_URL="https://raw.githubusercontent.com/ghzgod/unraid-docker-page-speedup/main/docker.page.speedup.plg"
SUPPORT_URL="https://github.com/ghzgod/unraid-docker-page-speedup"

# --- payload files (order: patcher, apply, revert, readme) -----------------
FILES=(dockerclient_speedup.py patch.sh unpatch.sh README.md)

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
<!ENTITY plugin  "$PLUGIN_URL">
<!ENTITY support "$SUPPORT_URL">
]>
<PLUGIN name="&name;" author="&author;" version="&version;" pluginURL="&plugin;" min="6.12" icon="bolt" support="&support;">

<CHANGES>
##$VERSION
- Speeds up the Unraid Docker page by caching template reads in DockerClient.php.
- getTemplates() dir listing + getTemplateValue() XML parsing are memoized per
  request, cutting O(containers x fields x templates) flash reads to O(templates).
- Measured ~37x faster template-scan on a 134-container / 246-template box.
- Re-applied at boot; idempotent; anchor-guarded; php -l verified with auto-rollback.
- No settings, no background service, no secrets.
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
bash /usr/local/emhttp/plugins/docker.page.speedup/patch.sh
echo "----------------------------------------------------"
echo " Docker Page Speedup installed."
echo " DockerClient.php template caching applied (re-applied on every boot)."
echo " Check: logger tag 'docker-page-speedup' in the syslog."
echo "----------------------------------------------------"
]]>
</INLINE>
</FILE>

<FILE Run="/bin/bash" Method="remove">
<INLINE>
<![CDATA[
bash /usr/local/emhttp/plugins/docker.page.speedup/unpatch.sh 2>/dev/null
rm -rf /usr/local/emhttp/plugins/docker.page.speedup
]]>
</INLINE>
</FILE>

</PLUGIN>
POSTINSTALL
} > "$OUT"

echo "Built $OUT ($VERSION) — secret-free, ${#FILES[@]} files embedded."
