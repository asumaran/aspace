# aspace

Tiny macOS utility that disconnects and reconnects displays without unplugging
the cable, plus a menu bar app that lets you flip between layouts in one click.

Built because I wanted to toggle between **walking on the treadmill with only
the TV active** and **working at the desk with the monitors back** — without
running a heavy menu bar app full of features I don't need.

## What's in the box

| Target            | What it is                                      |
|-------------------|-------------------------------------------------|
| `aspace`          | CLI to list, enable, disable, set-main displays |
| `Aspace.app`      | Menu bar app, one-click mode switching          |
| `DisplayKit`      | Swift library shared by both                    |

## Requirements

- macOS 13 or newer (built and tested on macOS 26 Tahoe, Apple Silicon)
- Xcode Command Line Tools (`xcode-select --install`)

## Build

```bash
# CLI
swift build -c release
cp .build/release/aspace /usr/local/bin/

# Menu bar app
./Scripts/build-app.sh
cp -r build/Aspace.app /Applications/
```

## CLI usage

```bash
aspace list                           # show every display
aspace disable <uuid>                 # take a display offline
aspace enable  <uuid>                 # bring it back
aspace main    <uuid>                 # make it the primary display
aspace mode    <name>                 # apply a named mode from config.json
aspace is-enabled <uuid>              # "on" or "off"
aspace is-main    <uuid>              # "true" or "false"
```

`aspace list` example output:

```
UUID                                   ID       ENABLED  MAIN   NAME
CD233C7A-6722-4046-A421-579C671BE97C   2        on       true   Studio Display
A98DE3E9-9016-4865-BAAE-2EF4805341B6   3        on       false  DELL U2723QE
6B111247-75E3-471D-BC65-C64100DE3187   4        on       false  LG TV SSCR2
```

## Configuration

Copy `config.example.json` to `~/.config/aspace/config.json` and replace the
placeholder UUIDs with the values from `aspace list`. Each mode lists which
displays to enable, which to disable, and optionally which one should end up
as the main display.

```json
{
  "modes": {
    "treadmill": {
      "enable":  ["6B111247-..."],
      "disable": ["CD233C7A-...", "A98DE3E9-..."]
    },
    "desk": {
      "enable":  ["CD233C7A-...", "A98DE3E9-..."],
      "disable": ["6B111247-..."],
      "main":     "CD233C7A-..."
    }
  }
}
```

Once that's in place, `aspace mode treadmill` and `aspace mode desk` apply the
layout. The menu bar app reads the same config and exposes one menu item per
mode.

## Menu bar app

`Aspace.app` runs as a menu bar accessory (no Dock icon). The icon changes
with the active mode (`figure.walk` for treadmill, `display` for desk,
`display.2` if the current layout matches no configured mode). Open the menu
to switch modes, see each display's connection / main state, or open the
config folder.

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
re-enabling, aspace persists a `UUID → displayID` map at
`~/.config/aspace/displays.json` and reuses the cached id. The disable uses
`CGConfigureOption.forSession`, so a reboot always brings every display back
and the cache becomes harmless if stale.

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
