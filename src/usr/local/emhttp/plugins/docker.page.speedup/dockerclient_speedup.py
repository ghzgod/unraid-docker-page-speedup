#!/usr/bin/env python3
# Idempotent, self-verifying performance patch for Unraid's Docker page.
#
# Target: /usr/local/emhttp/plugins/dynamix.docker.manager/include/DockerClient.php
#
# What it does (adds two in-request caches; changes NO behaviour):
#   Fix A/B  getTemplates()      -> memoize the per-request template dir listing
#   Fix D/E  getTemplateValue()  -> parse each template XML at most once/request
#
# Without these, a full Docker page render calls getTemplateValue() ~9x per
# container (WebUI, MyIP, Shell, Registry, Support, Project, DonateLink, ReadMe,
# Icon) and EACH call re-parses every template XML off the USB flash. That is
# O(containers * fields * templates) flash reads. The caches collapse it to
# O(templates) parses per request.
#
# Safety: writes only if all 4 exact anchors match (so it cleanly no-ops on any
# Unraid build whose code differs), and is a no-op if already patched. The
# caller is expected to `php -l` the result and roll back on any lint failure.
#
# Exit codes: 0 patched, 2 already-patched, 1 anchors-didn't-match (no write).
import sys

path = sys.argv[1] if len(sys.argv) > 1 else \
    "/usr/local/emhttp/plugins/dynamix.docker.manager/include/DockerClient.php"

with open(path) as f:
    c = f.read()
orig = c

if "templatesCache" in c or "cachedDoc" in c:
    print("ALREADY_PATCHED")
    sys.exit(2)

fixes = 0

# --- Fix A: declare getTemplates() memo cache + early return -----------------
A_old = ("\tpublic function getTemplates($type) {\n"
         "\t\tglobal $dockerManPaths;\n"
         "\t\t$tmpls = $dirs = [];")
A_new = ("\tprivate static $templatesCache = [];\n"
         "\tpublic function getTemplates($type) {\n"
         "\t\tglobal $dockerManPaths;\n"
         "\t\tif (isset(self::$templatesCache[$type])) return self::$templatesCache[$type];\n"
         "\t\t$tmpls = $dirs = [];")
if A_old in c:
    c = c.replace(A_old, A_new, 1); fixes += 1

# --- Fix B: populate getTemplates() memo cache before return ----------------
B_old = ("\t\tarray_multisort(array_column($tmpls,'name'), SORT_NATURAL|SORT_FLAG_CASE, $tmpls);\n"
         "\t\treturn $tmpls;\n"
         "\t}")
B_new = ("\t\tarray_multisort(array_column($tmpls,'name'), SORT_NATURAL|SORT_FLAG_CASE, $tmpls);\n"
         "\t\tself::$templatesCache[$type] = $tmpls;\n"
         "\t\treturn $tmpls;\n"
         "\t}")
if B_old in c:
    c = c.replace(B_old, B_new, 1); fixes += 1

# --- Fix D: add per-request XML-parse cache helper before getTemplateValue --
D_old = "\tpublic function getTemplateValue($Repository, $field, $scope='all',$name='') {"
D_new = ("\tprivate static $xmlCache = [];\n"
         "\tprivate function cachedDoc($path) {\n"
         "\t\tif (!isset(self::$xmlCache[$path])) { $d = new DOMDocument(); @$d->load($path); self::$xmlCache[$path] = $d; }\n"
         "\t\treturn self::$xmlCache[$path];\n"
         "\t}\n"
         "\tpublic function getTemplateValue($Repository, $field, $scope='all',$name='') {")
if D_old in c:
    c = c.replace(D_old, D_new, 1); fixes += 1

# --- Fix E: use the cache inside getTemplateValue ---------------------------
E_old = ("\t\t\t$doc = new DOMDocument();\n"
         "\t\t\t$doc->load($file['path']);")
E_new = "\t\t\t$doc = $this->cachedDoc($file['path']);"
if E_old in c:
    c = c.replace(E_old, E_new, 1); fixes += 1

if fixes != 4 or c == orig:
    sys.stderr.write("PATCH_ABORT: expected 4 anchors, matched %d (file left untouched)\n" % fixes)
    sys.exit(1)

with open(path, "w") as f:
    f.write(c)
print("PATCHED_OK 4")
sys.exit(0)
