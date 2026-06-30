# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

## [0.1.6]

- Baseline release. See git history for earlier changes.
