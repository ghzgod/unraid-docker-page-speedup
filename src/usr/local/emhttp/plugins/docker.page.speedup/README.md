# Docker Page Speedup

Makes the Unraid **Docker** page load dramatically faster on systems with many
containers, by fixing a long-standing inefficiency in how the webGUI reads
container templates from the USB flash boot device.

## The problem

Every time the Docker page renders, Unraid's `DockerClient.php` calls
`getTemplateValue()` about **nine times per container** — once each for WebUI,
MyIP, Shell, Registry, Support, Project, DonateLink, ReadMe and the icon. Each
of those calls **re-parses every template XML on the flash** from scratch. There
is no caching, so the total work is:

```
containers  ×  ~9 fields  ×  every template on the USB flash
```

On a box with a lot of containers that is tens of thousands of reads/parses of
files on the (slow) USB stick on **every single page load**, which is why the
Docker tab can take 1–2 minutes to appear.

Measured on a real system (134 containers, 246 templates), just **two** of those
nine per-container lookups already took **9.4 seconds**.

## The fix

This plugin adds two small in-request caches to `DockerClient.php`:

- **`getTemplates()`** — memoizes the template directory listing per request.
- **`getTemplateValue()`** — parses each template XML **at most once** per
  request (via a small `cachedDoc()` helper) instead of once per lookup.

Behaviour is identical; only the redundant flash reads are removed. The work
drops from `O(containers × fields × templates)` to `O(templates)`.

**Same 9.4 s workload after patching: 0.25 s (~37× faster).**

## How it works / safety

- The webGUI lives in RAM and is rebuilt stock on every boot, so the patch is
  re-applied at boot. Unraid re-runs `plugin install` for every `.plg` at boot
  (`/etc/rc.d/rc.local`), which triggers `patch.sh`.
- **Idempotent** — never patches an already-patched file.
- **Anchor-guarded** — it only edits if all four exact code anchors match, so on
  any Unraid build whose code differs it cleanly does nothing (no breakage).
- **Verified** — runs `php -l` after patching and **automatically rolls back** to
  the stock file if the result doesn't parse.
- Logs every action to syslog under the tag `docker-page-speedup`.

Verified on **Unraid 7.2.3 → 7.3.2**. (The related 7.2.3 icon-fetch storm was
fixed upstream in 7.3.x; this plugin addresses the template-scan half, which is
still present.)

## Install

Add the `.plg` URL under **Plugins → Install Plugin**:

```
https://raw.githubusercontent.com/ghzgod/unraid-docker-page-speedup/main/docker.page.speedup.plg
```

## Uninstall

Remove it from the **Plugins** page. That restores the stock `DockerClient.php`
(from the backup taken at patch time; a reboot also restores it regardless).
