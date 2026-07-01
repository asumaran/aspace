# aspace

Tiny macOS utility that disconnects and reconnects displays without unplugging
the cable, plus a menu bar app that switches between display layouts in one
click.

Useful for any setup where you want fast, scriptable control over which
displays are active:

- Switch between a multi-monitor workstation and a single-display focus mode
- Drop down to one screen for an exercise bike, treadmill desk, or couch
  session, then bring everything back at the desk
- Hide secondary monitors during presentations or screen recordings
- Park unused displays so macOS stops placing windows on them when you step
  away from the desk
- Save power on a laptop by quickly cutting external displays off the bus
- Apply a named layout (`aspace profile name`) from a shell script, Shortcut,
  Stream Deck button, or any other automation

Reach for it when you just want disconnect / reconnect / pick-a-main, without
the surface area of a full monitor manager.

## What's in the box

| Target            | What it is                                      |
|-------------------|-------------------------------------------------|
| `aspace`          | CLI to list, enable, disable, set-main displays |
| `Aspace.app`      | Menu bar app, one-click profile switching       |
| `DisplayKit`      | Swift library shared by both                    |

## Requirements

- macOS 13 or newer (built and tested on macOS 26 Tahoe, Apple Silicon)

## Install

### From a pre-built release (recommended)

Only Apple Silicon binaries are published. Pick a version from the
[releases page](https://github.com/asumaran/aspace/releases) and:

```bash
VERSION=v0.1.6

# CLI
curl -fL -o /tmp/aspace.tar.gz \
  "https://github.com/asumaran/aspace/releases/download/${VERSION}/aspace-${VERSION}-darwin-arm64.tar.gz"
tar -xzf /tmp/aspace.tar.gz -C /tmp
install -m 0755 /tmp/aspace ~/.local/bin/aspace   # anywhere on your $PATH

# Menu bar app
curl -fL -o /tmp/Aspace.app.zip \
  "https://github.com/asumaran/aspace/releases/download/${VERSION}/Aspace-${VERSION}.app.zip"
ditto -xk /tmp/Aspace.app.zip /Applications
xattr -dr com.apple.quarantine /Applications/Aspace.app
```

### Build from source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/asumaran/aspace.git
cd aspace
make install   # builds CLI + app and installs to ~/.local/bin and /Applications
```

Other Makefile targets: `make` (build only), `make test`, `make uninstall`,
`make clean`, `make help`. Override install locations with
`make install PREFIX=/usr/local APP_DEST=~/Applications`.

## CLI usage

```bash
aspace list                           # show every display
aspace modes [<uuid>]                 # list a display's supported resolutions
aspace disable <uuid>                 # take a display offline
aspace enable  <uuid>                 # bring it back
aspace main    <uuid>                 # make it the primary display
aspace profile <name>                 # apply a profile (topology: on/off + main)
aspace profiles                       # list available profile names
aspace capture <name>                 # save the current topology as a profile
aspace resolution <name>              # apply a resolution preset (scaling only)
aspace resolutions                    # list available resolution preset names
aspace capture-resolution <name>      # save current resolutions as a preset
aspace is-enabled <uuid>              # "on" or "off"
aspace is-main    <uuid>              # "true" or "false"
```

The built-in `all` profile is always available and reconnects every display
aspace knows about (equivalent to a profile with an empty `disable` list) —
handy as a "back to normal" shortcut.

`aspace list` example output:

```
UUID                                   ID       ENABLED  MAIN   RESOLUTION   NAME
A1B2C3D4-1111-2222-3333-444455556666   1        on       true   1512x982     Built-in Retina Display
B2C3D4E5-2222-3333-4444-555566667777   2        on       false  2560x1440    External 4K Display
C3D4E5F6-3333-4444-5555-666677778888   3        on       false  3200x1800    Secondary Monitor
```

The `RESOLUTION` column shows each display's current "looks like" size (the
HiDPI point size from System Settings, not the raw pixel count).

## Configuration

Copy `config.example.json` to `~/.config/aspace/config.json` and replace the
placeholder UUIDs with the values from `aspace list`. Each profile lists the
UUIDs to **disconnect**; every other known display stays (or becomes)
enabled. This is "allow by default" — adding a new monitor or fat-fingering
a UUID can never accidentally take all your screens offline. If a profile
would leave zero displays enabled, aspace refuses to apply it.

```json
{
  "profiles": {
    "focus": {
      "disable": ["B2C3D4E5-...", "C3D4E5F6-..."]
    },
    "workstation": {
      "disable": ["C3D4E5F6-..."],
      "main":    "B2C3D4E5-..."
    }
  },
  "resolutions": {
    "cozy":     { "B2C3D4E5-...": "2560x1440", "A1B2C3D4-...": "2560x1440" },
    "spacious": { "B2C3D4E5-...": "3200x1800", "A1B2C3D4-...": "3200x1800" }
  }
}
```

Profile names are free-form — pick whatever maps to your workflow (`focus`,
`workstation`, `presentation`, `couch`, `recording`, etc.). The built-in
`all` profile is always available (no config needed) and reconnects every
known display.

Once the config is in place, `aspace profile <name>` applies the layout.
The menu bar app reads the same config on every menu open and exposes one
item per profile plus a built-in "Reconnect all displays".

`main` is optional. When a profile leaves a single display enabled, aspace
automatically makes that lone display the main — which also re-homes its
origin to (0, 0), so the cursor and menu bar stay reachable (otherwise a
single-display profile can strand the pointer in the old multi-display
coordinate space). When two or more displays remain and `main` is omitted,
macOS keeps the previous main where possible; declare `main` explicitly only
when you care which one is the primary.

### Resolution presets

`resolutions` is a separate axis from profiles. A preset maps display UUIDs to
a target resolution and is applied with `aspace resolution <name>` (or from the
menu bar) **without touching connections or the main display** — so you can
flip the same set of monitors between, say, a `cozy` larger-text layout in the
morning and a `spacious` one during the day:

```bash
aspace resolution cozy       # bigger text
aspace resolution spacious   # more screen real estate
```

Because it only changes scaling on already-connected displays, switching is
fast and flicker-free — handy to bind to a keyboard shortcut, a Shortcut, or a
`launchd`/`cron` job that flips it on a schedule.

The value is the "looks like" point size from System Settings (e.g.
`"2560x1440"`), not the raw pixel count. A single point size maps to several
underlying modes (HiDPI vs 1:1, different refresh rates); aspace resolves that
by preferring the HiDPI mode at the highest refresh rate. A resolution a
display doesn't support, or a display that's currently off, is skipped with a
warning rather than applied. Run `aspace modes <uuid>` to see the point sizes a
display actually supports before writing a preset.

### Capturing the current state

Rather than hand-writing UUIDs, arrange things the way you want in System
Settings and snapshot them:

```bash
aspace capture workstation         # topology: main + which displays are off
aspace capture-resolution spacious # current resolution of every on display
```

`capture` records the main display and lists any known-but-disconnected
displays under the profile's `disable`. `capture-resolution` records each on
display's current resolution as a preset. Both overwrite an entry of the same
name and leave the rest of the config untouched.

## Menu bar app

`Aspace.app` runs as a menu bar accessory (no Dock icon). The icon reflects
the active profile via SF Symbols: `display.2` when every known display is
enabled (the built-in `all` profile), and `rectangle.on.rectangle.slash`
when the live layout matches no configured profile. A few well-known
profile names get themed icons baked in (`treadmill` → `figure.walk`,
`desk` → `display`); any other name falls back to the generic icon. Open
the menu to switch profiles or jump to the config folder. A `Displays`
submenu lists each screen with a colored status dot — 🟢 active, ⚪️ inactive
or offline — and the main display is tagged `(main)`. It also surfaces
displays referenced by your config (a profile's `disable`/`main`, or a
resolution preset) that are disconnected right now, so a powered-off monitor
you manage still appears instead of vanishing.

## How it works (and how it might break)

- **Listing / detection**: only public CoreGraphics + `NSScreen` APIs.
- **Setting the main display**: public `CGConfigureDisplayOrigin`, by shifting
  every display so the chosen one lands at (0, 0).
- **Resolutions**: public `CGDisplayCopyAllDisplayModes` /
  `CGConfigureDisplayWithDisplayMode`. Only modes the panel actually reports
  can be applied, so an unsupported resolution is impossible to force — it's
  skipped with a warning.
- **Enable / disable**: the private `CGSConfigureDisplayEnabled` symbol
  (CoreGraphics, re-exported from `SkyLight.framework`). Apple has shipped
  it stable for years, but it's undocumented and could disappear in a
  future macOS. If that happens, `list` and `main` keep working; the rest
  doesn't.

When a display is disabled, it disappears from `CGGetOnlineDisplayList` and
its `CGDirectDisplayID` is no longer discoverable by UUID. To handle
re-enabling, aspace persists a `UUID → displayID` (plus name) map at
`~/.config/aspace/displays.json` and reuses the cached id. The disable uses
`CGConfigureOption.forSession`, so a reboot always brings every display back
and the cache becomes harmless if stale.

If a cached entry no longer maps to a real display (transient AirPlay,
Sidecar, briefly-opened laptop lid, etc.), the runner skips it with a
warning instead of aborting; cleanup happens manually via
`aspace prune [days]`.

## Development

### Layout

Three Swift targets:

- `DisplayKit` — the library where all the real logic lives: config parsing,
  profile/resolution application, display-mode selection. It talks to
  CoreGraphics through a small `DisplayBackend` seam, so the decision-making
  parts are pure and value-based.
- `AspaceCLI` (the `aspace` binary) and `AspaceApp` (the menu bar app) — thin
  shells that parse input / render the menu and call into `DisplayKit`.

When adding behavior, put the logic in `DisplayKit` (with tests) and keep the
CLI/app as glue. The existing pure helpers — `ProfileRunner`,
`ResolutionRunner`, `ResolutionState`, `DisplayModeMatcher`,
`DisplayModeReport`, `ProfileCapture` — follow that pattern.

### Unit tests

```bash
make test        # or: swift test
```

Tests live in `Tests/DisplayKitTests` and use
[swift-testing](https://github.com/swiftlang/swift-testing) (`@Suite`/`@Test`/
`#expect`). They never touch real displays: `ProfileRunner` and
`ResolutionRunner` run against a `FakeBackend` that records the operations they
issue, and the mode-selection / state helpers are exercised with synthetic
`DisplayMode` values. Mirror that when adding tests — drive the seam, don't
poke CoreGraphics.

### Testing the CLI

```bash
swift build                       # debug build at .build/debug/aspace
.build/debug/aspace list
.build/debug/aspace modes <uuid>
```

CLI commands act on live displays, so they double as a manual integration
check (`list`, `modes`, `resolution <name>`, `profile <name>`).

### Testing the menu bar app

`AspaceApp` has **no unit-test target** — its logic is pushed down into
`DisplayKit` (e.g. `ResolutionState` backs the menu's active-preset checkmark
and the dimming of presets that don't apply), which *is* tested. The app shell
itself is verified by building and running it:

```bash
make app                          # builds CLI + build/Aspace.app
pkill -x Aspace 2>/dev/null       # stop any running instance first
open build/Aspace.app             # run the freshly built bundle (no install)
```

`open build/Aspace.app` runs the local build without replacing an installed
copy in `/Applications`; quitting it and relaunching the installed app reverts.
Use `make install` only when you want the new build to become the installed one
(it stops the running instance, then copies the CLI and app into place).

Manual smoke test after an app change: open the menu, switch between profiles
and resolution presets, confirm the `✓` tracks the active preset and that
presets whose displays are all offline appear dimmed. The app listens for
display-reconfiguration events, so changing resolution by any other means
should update the menu on its own.

### Logs

aspace logs every profile/resolution operation and a per-display topology
snapshot through the unified log (`os.Logger`, subsystem
`com.asumaran.aspace`), at a level macOS persists. So when a display switch
misbehaves, reproduce it and then read what actually happened — which displays
were enabled/disabled, the main chosen, the modes set, and the resulting
resolutions:

```bash
Scripts/logs.sh                 # last 5 minutes
Scripts/logs.sh --stream        # follow live
Scripts/logs.sh --last 10m      # custom window
```

The same entries are visible in Console.app by filtering on the subsystem.

## Releasing

Cut a release with the helper script — it is the whole process:

```bash
Scripts/release.sh 0.3.0            # gate, generate CHANGELOG, commit, tag, push
Scripts/release.sh 0.3.0 --dry-run  # preview the version + CHANGELOG, change nothing
```

It refuses to run unless you are on a clean `main`, runs `make test` and
`make app` as a gate, generates the CHANGELOG section from the commit subjects
since the previous tag (no hand-editing), then commits `chore(release): vX.Y.Z`,
tags, and pushes.

Pushing the tag `vX.Y.Z` triggers `.github/workflows/release.yml`, which
builds, packages, and publishes the CLI tarball + `.app.zip` to a new
GitHub Release. The workflow looks for these optional repo secrets and
upgrades the release accordingly:

| Secret | Effect when set |
|--------|-----------------|
| `APPLE_DEVELOPER_CERT_B64` + `APPLE_DEVELOPER_CERT_PASS` + `APPLE_DEVELOPER_TEAM_ID` | Signs the app with Developer ID instead of ad-hoc |
| `APPLE_NOTARY_USER` + `APPLE_NOTARY_PASS` (and the cert above) | Submits to Apple notary service and staples the ticket |
| `SPARKLE_PRIVATE_KEY` (and `SPARKLE_PUBLIC_KEY` baked into `Info.plist` at build time) | Signs the update zip and appends the entry to `appcast.xml`, then commits/pushes the appcast back to `main` |

Without any secrets the workflow still produces a working release —
just ad-hoc signed and without auto-update support. See
[docs/RELEASE_SECRETS.md](docs/RELEASE_SECRETS.md) for how to generate
each value.

## Compared to BetterDisplay / Lunar

This is intentionally a sliver of what those apps do. It doesn't manage
brightness, virtual screens, color profiles, refresh rates, DDC, HDR
protection, or anything else. If you need any of that, use one of them
instead.

## Prior art and credit

The `CGSConfigureDisplayEnabled` symbol has been used and documented by
several open-source projects over the years. Useful references:

- [`displayplacer/src/Header.h`](https://github.com/jakehilborn/displayplacer/blob/master/src/Header.h)
  declares the C signature alongside other private CoreGraphics symbols.
- [`oabdrabo/DisplayDisabler`](https://github.com/oabdrabo/DisplayDisabler#how-it-works)
  has a short prose explanation of how the symbol takes a display offline
  at the compositor level.

Note that Lunar and BetterDisplay achieve a comparable disconnect / blackout
user experience but with different mechanisms — Lunar uses DDC commands or
mirror-mode tricks (no `CGSConfigureDisplayEnabled` in its source);
BetterDisplay's implementation is closed source.

## License

[MIT](LICENSE)
