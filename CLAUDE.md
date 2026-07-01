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

### Getting onto a newly published release — order to suggest

1. **In-app Sparkle auto-update first** ("Check for Updates"). This is the
   intended path and works *only* on a build installed from a published release:
   the published `.app.zip` carries `SUPublicEDKey` (the EdDSA trust anchor) and
   a `CFBundleVersion` matching the appcast.
2. **Install the published artifact** if auto-update can't run — download the
   release `Aspace-vX.Y.Z.app.zip` and replace `/Applications/Aspace.app`. This
   also restores auto-update capability for future releases.
3. **`make install` from source** as a last resort / for local dev only.

Important caveat: a `make install` (or `make app`) build is ad-hoc signed and
has **no `SUPublicEDKey`** (the Sparkle public key is injected from a CI secret,
absent locally). Such a build finds updates via `SUFeedURL` and shows the
prompt, but Sparkle cannot verify the signed download and the install fails. So
on a locally-built app, do not suggest auto-update as actionable — point to
option 2. Verify with:
`/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" /Applications/Aspace.app/Contents/Info.plist`
(absent ⇒ auto-update won't complete).

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

## Debugging with logs

Don't guess at display behavior — read the logs. aspace logs every
profile/resolution operation (the plan, each enable/disable/setMain/setMode with
its result) and a per-display topology snapshot (UUID, main, enabled, current
mode) through `os.Logger`, subsystem `com.asumaran.aspace`, at the `.notice`
level. macOS persists `.notice`, so the workflow is: have the user reproduce,
then read what actually happened — no live capture needed. The same entries
appear in Console.app (filter by the subsystem).

```bash
Scripts/logs.sh                    # last 5 minutes
Scripts/logs.sh --last 2m          # custom window
Scripts/logs.sh --stream           # follow live
Scripts/logs.sh --category ProfileRunner   # one category (App, ProfileRunner, …)
```

Keep new diagnostic logging at `.notice` and mark dynamic values
`privacy: .public` (the unified log redacts them otherwise). Log decisions and
results — never add CoreGraphics calls just to log; an extra reconfiguration in
the volatile window right after a topology change can destabilize the display
layout.

## Conventions

- Commit messages: Conventional Commits (`type(scope): description`). They are
  the source of the changelog (see Releasing), so keep subjects clear.
- Keep docs in sync when adding commands/config: `README.md` and
  `config.example.json`. Do **not** hand-edit `CHANGELOG.md` — `Scripts/release.sh`
  generates each version's entry from the commit subjects since the last tag.
- Do not commit or push unless asked.
- After changes that affect the app, offer to reinstall it — see "Installing /
  reinstalling the app".

## Releasing

`Scripts/release.sh X.Y.Z` is the whole process: it gates on a clean `main` +
`make test` + `make app`, generates the `CHANGELOG.md` section from the commit
subjects since the previous tag (filtering CI's `chore(release)`/`chore(appcast)`
commits), commits `chore(release): vX.Y.Z`, tags, and pushes. Pushing the tag
triggers `.github/workflows/release.yml` (build, sign, notarize, Sparkle appcast,
GitHub Release). Use `--dry-run` to preview, `--no-push` to stop before pushing.
Do not assemble releases by hand or hand-write the changelog.
