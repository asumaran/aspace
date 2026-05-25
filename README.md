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
# CLI
swift build -c release
cp .build/release/aspace ~/.local/bin/

# Menu bar app
./Scripts/build-app.sh
cp -R build/Aspace.app /Applications/
```

## CLI usage

```bash
aspace list                           # show every display
aspace disable <uuid>                 # take a display offline
aspace enable  <uuid>                 # bring it back
aspace main    <uuid>                 # make it the primary display
aspace profile <name>                 # apply a profile (see Configuration)
aspace profiles                       # list available profile names
aspace is-enabled <uuid>              # "on" or "off"
aspace is-main    <uuid>              # "true" or "false"
```

The built-in `all` profile is always available and reconnects every display
aspace knows about (equivalent to a profile with an empty `disable` list) —
handy as a "back to normal" shortcut.

`aspace list` example output:

```
UUID                                   ID       ENABLED  MAIN   NAME
A1B2C3D4-1111-2222-3333-444455556666   1        on       true   Built-in Retina Display
B2C3D4E5-2222-3333-4444-555566667777   2        on       false  External 4K Display
C3D4E5F6-3333-4444-5555-666677778888   3        on       false  Secondary Monitor
```

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

`main` is optional. When omitted, macOS keeps the previous main display
where possible — declare `main` explicitly only when the profile has 2+
enabled displays and you care which one is the primary.

## Menu bar app

`Aspace.app` runs as a menu bar accessory (no Dock icon). The icon reflects
the active profile via SF Symbols: `display.2` when every known display is
enabled (the built-in `all` profile), and `rectangle.on.rectangle.slash`
when the live layout matches no configured profile. A few well-known
profile names get themed icons baked in (`treadmill` → `figure.walk`,
`desk` → `display`); any other name falls back to the generic icon. Open
the menu to switch profiles, inspect each display's connection / main
state, or jump to the config folder.

## How it works (and how it might break)

- **Listing / detection**: only public CoreGraphics + `NSScreen` APIs.
- **Setting the main display**: public `CGConfigureDisplayOrigin`, by shifting
  every display so the chosen one lands at (0, 0).
- **Enable / disable**: the private `CGSConfigureDisplayEnabled` symbol — the
  same one Lunar's BlackOut and BetterDisplay use under the hood. Apple has
  shipped it stable for years, but it's undocumented and could disappear in a
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

## Releasing

Tagging `vX.Y.Z` on `main` triggers `.github/workflows/release.yml`, which
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

The private API trick (`CGSConfigureDisplayEnabled`) is documented in
[Lunar's source](https://github.com/alin23/Lunar) — that's where I learned
how the disconnect plumbing works.

## License

[MIT](LICENSE)
