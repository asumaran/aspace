# CLAUDE.md

Guidance for working in this repo. See `README.md` for user-facing docs and a
fuller "Development" section.

## What this is

`aspace` is a minimal macOS display-control tool: a CLI (`aspace`) and a menu
bar app (`Aspace.app`), both thin shells over a `DisplayKit` library. It
connects/disconnects displays, sets the main display, and switches resolutions
via named presets. Config lives at `~/.config/aspace/config.json`.

## Architecture (where to put code)

Three Swift targets:

- `DisplayKit` — all real logic. CoreGraphics access is behind the
  `DisplayBackend` seam, so decision-making code is pure and value-based.
- `AspaceCLI` / `AspaceApp` — glue. Parse input or render the menu, then call
  `DisplayKit`.

Rule: new behavior goes in `DisplayKit` with unit tests; keep the CLI and app
as thin wiring. Follow the existing pure helpers — `ProfileRunner`,
`ResolutionRunner`, `ResolutionState`, `DisplayModeMatcher`, `DisplayModeReport`,
`ProfileCapture`. Profiles control topology (which displays are on + the main);
`resolutions` are an independent axis that only changes scaling.

Design philosophy to preserve: non-destructive. A missing/offline display or an
unsupported mode is skipped with a warning, never aborts the operation; the
runner refuses any profile that would leave zero displays enabled.

## Build / test / run

```bash
make test                     # unit tests (swift test); Tests/DisplayKitTests
swift build                   # debug CLI at .build/debug/aspace
make app                      # build CLI + build/Aspace.app
make install                  # install to ~/.local/bin + /Applications (kills running app)
```

Tests use swift-testing (`@Suite`/`@Test`/`#expect`). They must not touch real
displays: drive `ProfileRunner`/`ResolutionRunner` through `FakeBackend`, and
test mode logic with synthetic `DisplayMode` values.

## Installing / reinstalling the app

When the user asks to install / reinstall / update aspace, act immediately;
don't over-explain. From the repo root:

```bash
make install                  # rebuilds CLI + app, installs them, stops the running app
open /Applications/Aspace.app # relaunch the menu bar app
```

`make install` installs the CLI to `~/.local/bin/aspace` and the app to
`/Applications`, stopping the running instance (`pkill -x Aspace`) before
copying. Verify afterward: `pgrep -lf /Applications/Aspace.app` and
`aspace version`.

Offer this proactively — the running `/Applications/Aspace.app` keeps executing
the previously installed build, so it won't reflect changes to `AspaceApp` (or
to `DisplayKit` code the app uses) until reinstalled and relaunched. Suggest it
after any such change and after a release. (The CLI at `~/.local/bin/aspace` is
likewise stale until reinstalled, but a fresh `.build/debug/aspace` always
reflects the working tree for quick checks.)

## Verifying changes

- `DisplayKit` / CLI: add or run unit tests, and exercise the live CLI
  (`.build/debug/aspace list | modes <uuid> | resolution <name>`).
- `AspaceApp`: there is **no app test target**. Push logic into `DisplayKit`
  (tested) and verify the shell by running it:
  ```bash
  make app && pkill -x Aspace 2>/dev/null; open build/Aspace.app
  ```
  Then open the menu and check the behavior (profile/resolution switching, the
  `✓` on the active preset, dimming of presets whose displays are offline).
  `open build/Aspace.app` runs the local build without replacing an installed
  copy.

## Conventions

- Commit messages: Conventional Commits (`type(scope): description`).
- Keep docs in sync when adding commands/config: `README.md`,
  `config.example.json`, and `CHANGELOG.md` (`[Unreleased]`).
- Do not commit or push unless asked.
- After changes that affect the app, offer to reinstall it — see "Installing /
  reinstalling the app".
