# Changelog

All notable changes to this project are documented here, newest first, under a
`## X.Y.Z (date)` heading. Entries through 0.2.2 were written by hand in the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) style; newer ones are
generated from the commit log by `Scripts/release.sh`. The project aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.4.0 (2026-08-05)

* feat: make post-switch stabilization optional (3a7ac5b)
* feat(app): always-on sole-display guard (5221040)
* fix(displaykit): restore main display after aborted switch (c1a4239)
* feat(displaykit): post-switch stabilization watchdog (41e73ab)
* docs(readme): document audio and new menu behavior (c1ede95)
* feat(app): rebuild menu bar dropdown in AppKit (5b3a4c6)
* feat(displaykit): add profile summary helper (1a45b09)
* feat(cli): add audio and audio-outputs commands (b33b670)
* feat(displaykit): per-profile audio output switching (5f9f311)
* build(release): gate on version-format consistency (c832893)
* docs(changelog): normalize version heading format (41708ec)

## 0.3.0 (2026-07-01)

* feat(app): add menu toggle to disable resolution restore (1746cde)
* perf(profile): batch enable/disable into a single reconfiguration (82d5279)
* docs+logging: expand the debugging toolkit (98b7534)
* test(profile): simulate the TV's real failure modes (4f23668)
* feat(cli): add --dry-run to preview a profile without applying it (6bae7a4)
* fix(app): run profile/resolution switches off the main thread (9d91a88)
* feat(app): restore the last resolution preset after a profile switch (003eff9)
* fix(profile): reliable single-display switches, cursor recovery, detection (321fcfe)
* docs: document log-based debugging (dcde3b9)
* build(logging): add Scripts/logs.sh to read the unified log (6f9bbe8)
* feat(logging): trace profile/resolution operations and topology (d949ee8)

## 0.2.3 (2026-06-30)

* docs: drive releases and the changelog from Scripts/release.sh (13bba7e)
* build(release): add Scripts/release.sh to automate cutting releases (7fb2897)
* docs: auto-main behavior and the active-profile detection fix (cd40d0a)
* fix(menu): ignore registry ghosts when detecting the active profile (37e2c89)
* feat(profile): auto-set main on the sole surviving display (ada1250)

## 0.2.2 (2026-06-30)

### Added

- The menu bar app surfaces **offline displays** in the `Displays` list: a
  screen that is disconnected or powered off but referenced by your config
  (a profile's `disable`/`main`, or a resolution preset) now appears with a
  ⚪️ marker instead of silently vanishing. Displays the registry has only seen
  incidentally, or with no recorded name, are omitted to avoid stale "ghost"
  rows.

### Changed

- The menu's display list moved into a `Displays` submenu and now shows status
  with a colored dot — 🟢 active, ⚪️ inactive/offline — replacing the previous
  monochrome `●`/`○` text.

## 0.2.1 (2026-06-30)

### Fixed

- Sparkle no longer offers a spurious "update available" to the version already
  installed. The app bundle stamped its `CFBundleVersion` with the `v`-prefixed
  `git describe` string (e.g. `v0.2.0`) while the appcast publishes the version
  without the prefix (`0.2.0`); Sparkle read the two as different and flagged an
  update. The build now strips the leading `v` from `CFBundleVersion` /
  `CFBundleShortVersionString` so they match the appcast.

## 0.2.0 (2026-06-30)

### Added

- **Resolution presets.** A new `resolutions` section in `config.json` maps
  display UUIDs to a target "looks like" point size (e.g. `"2560x1440"`).
  Presets are an axis independent of profiles: applying one changes only the
  resolution of the listed displays, never connecting/disconnecting displays
  or changing the main. Switching is fast and flicker-free.
  - `aspace resolution <name>` — apply a preset.
  - `aspace resolutions` — list preset names.
  - A single point size can map to several underlying modes (HiDPI vs 1:1,
    different refresh rates); aspace resolves the ambiguity by preferring the
    HiDPI mode at the highest refresh rate. Unsupported sizes and offline
    displays are skipped with a warning instead of aborting.
- **`aspace modes [<uuid>]`** — list the resolutions a display supports
  (points, pixels, scaling, refresh), marking the current mode. Use the
  reported point size when writing a preset. Defaults to all online displays.
- **`aspace capture <name>`** — save the current topology (main display plus
  any known-but-off displays as `disable`) as a profile.
- **`aspace capture-resolution <name>`** — save the current resolution of every
  on display as a resolution preset.
- **Menu bar resolution switching.** The dropdown gained a "Resolution" section
  listing presets, with a checkmark on the active one. Presets whose displays
  are all offline are dimmed, so the menu only offers what applies to the
  currently connected displays.

### Changed

- `aspace list` now includes a `RESOLUTION` column showing each display's
  current point size.

### Internal

- `DisplayKit` gained value-based, CoreGraphics-free helpers so the new logic
  is unit-tested: `DisplayMode`/`DisplayModeMatcher` (mode selection),
  `DisplayModeReport` (listing order), `ResolutionRunner` (preset application),
  `ResolutionState` (active/applicable preset queries), and `ProfileCapture`
  (snapshot → config). Mode reads/writes use the public
  `CGDisplayCopyAllDisplayModes` / `CGConfigureDisplayWithDisplayMode` APIs.

## 0.1.6 (2026-05-24)

- Baseline release. See git history for earlier changes.
