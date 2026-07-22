# Docker Page Speedup

An Unraid plugin that makes the **Docker** page load dramatically faster **and**
reduces its CPU/GPU load on systems with many containers — with a settings page
to tune both.

## Two optimizations

### 1. Page-load speedup (template caching)

Every time the Docker page renders, Unraid's `DockerClient.php` calls
`getTemplateValue()` about **nine times per container** (WebUI, MyIP, Shell,
Registry, Support, Project, DonateLink, ReadMe, icon). Each call **re-parses
every container-template XML on the USB flash** from scratch — no caching — so the
work is `O(containers × ~9 fields × templates)`. On a busy box that's tens of
thousands of flash reads on **every page load** (1–2 minute loads).

The plugin adds two in-request caches to `DockerClient.php`:

- `getTemplates()` — memoizes the template directory listing per request.
- `getTemplateValue()` — parses each template XML at most once per request.

Behaviour is identical; only the redundant flash reads are removed —
`O(containers × fields × templates)` → `O(templates)`.

**Measured on a real box (134 containers, 246 templates), real `getAllInfo()`:**

| Load type | Stock | With plugin | Speedup |
|---|---|---|---|
| Cold (cache empty / after boot) | 38.46 s | 4.10 s | ~9× |
| Warm (steady state) | 3.93 s | 0.07 s | ~56× |

### 2. Docker stats refresh interval (CPU/GPU load)

While the Docker page is open, Unraid's `nchan/docker_load` pusher runs
`docker stats` on **every** container **every second** and the browser repaints
the whole table each second — heavy on CPU and on the client GPU. The plugin lets
you throttle that interval (default **5 s**), sharply cutting the load. Setting it
to `1` is the Unraid stock behaviour.

## Settings

**Settings → Utilities → Docker Page Speedup** (or click the plugin's bolt icon on
the Plugins page):

- **Page-load speedup** — Enabled / Disabled (Disabled restores the stock file).
- **Docker stats refresh interval** — 1 (stock) / 2 / 3 / 5 / 10 / 15 seconds.

Config persists at `/boot/config/plugins/docker.page.speedup/docker.page.speedup.cfg`.

## How it works / safety

- The webGUI lives in RAM and is rebuilt stock on every boot, so both patches are
  re-applied at boot. This uses Unraid's **documented** behaviour: at boot
  `rc.local` runs `plugin install` for every `.plg` in `/boot/config/plugins`,
  which runs the plugin's install script (`apply.sh`).
- **Config-driven & idempotent** — `apply.sh` reads the saved config and makes the
  live files match; never double-patches.
- **Anchor-guarded** — the `DockerClient.php` patch only edits if all four exact
  code anchors match, so on any Unraid build whose code differs it does nothing
  (verified: it aborts and leaves the file byte-for-byte untouched).
- **Verified** — runs `php -l` after patching and **auto-rolls-back** to stock on
  any parse error.
- **Reversible** — a stock backup of each file is kept; uninstall restores both,
  and a reboot restores stock regardless. Logs to syslog tag `docker-page-speedup`.

> Note: there is no official Unraid hook to change these functions, so the plugin
> patches two stock webGUI files (`DockerClient.php`, `nchan/docker_load`) in place.
> This is inherently invasive by necessity, but done with the safeguards above.

Verified on **Unraid 7.2.3 → 7.3.2**.

## Install

**Plugins → Install Plugin**:

```
https://raw.githubusercontent.com/ghzgod/unraid-docker-page-speedup/main/docker.page.speedup.plg
```

## Uninstall

Remove it from the **Plugins** page — restores stock `DockerClient.php` and
`docker_load`.

## Build

`./build.sh [version]` regenerates `docker.page.speedup.plg` from `src/` (inline,
secret-free).
