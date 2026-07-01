#!/usr/bin/env bash
#
# release.sh — cut a new aspace release from a clean, green tree.
#
# A release is driven entirely by a tag: pushing `vX.Y.Z` triggers
# .github/workflows/release.yml, which builds + signs + notarizes the app,
# packages the CLI tarball and .app.zip, signs the update with Sparkle, appends
# the entry to appcast.xml (and pushes it back to main), and publishes the
# GitHub Release. This script prepares and pushes that tag so we never release a
# broken or half-committed state:
#
#   1. must be on `main` with a clean working tree (the tag == exactly what is
#      committed)
#   2. `make test` and `make app` must pass
#   3. the CHANGELOG section is generated from the commit subjects since the
#      previous tag — there is nothing to write by hand
#
# The version is the only thing you pick; everything else is derived.
#
# Usage:
#   Scripts/release.sh 0.3.0             # release 0.3.0 (commit, tag, push)
#   Scripts/release.sh 0.3.0 --no-push   # do everything locally, skip the push
#   Scripts/release.sh 0.3.0 --dry-run   # print the version + CHANGELOG, change nothing
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DO_PUSH=true
DRY_RUN=false
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --no-push) DO_PUSH=false ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)        echo "unknown argument: $arg" >&2; exit 2 ;;
    *)         VERSION="$arg" ;;
  esac
done

if [ -z "$VERSION" ]; then
  echo "error: version required, e.g. Scripts/release.sh 0.3.0" >&2
  exit 2
fi
if ! printf '%s' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "error: '$VERSION' is not a valid X.Y.Z version" >&2
  exit 2
fi

tag="v${VERSION}"

# --- collect commits since the last tag (for the CHANGELOG) -----------------
# The new CHANGELOG section is just the commit subjects since the previous tag.
# CI-generated bookkeeping commits (the release bump and the appcast publish)
# are filtered out so they never read as user-facing "changes".
prev_tag="$(git tag --list 'v*' --sort=-version:refname | head -n1 || true)"
date_str="$(date +%Y-%m-%d)"
if [ -n "$prev_tag" ]; then
  log_range="${prev_tag}..HEAD"
else
  log_range="HEAD"
fi
commits="$(git log --no-merges --pretty='format:* %s (%h)' "$log_range" \
  | grep -vE '^\* chore\((release|appcast)\): ' || true)"
if [ -z "$commits" ]; then
  commits="* No changes since ${prev_tag:-the start}."
fi
# Heading uses the bare X.Y.Z (no leading "v") to match the version numbers
# used everywhere else (appcast sparkle:version, the bundle CFBundleVersion);
# the "v" lives only in the git tag and asset names.
new_section="$(printf '## %s (%s)\n\n%s' "$VERSION" "$date_str" "$commits")"

# --- dry run: show what would happen, touch nothing -------------------------
if $DRY_RUN; then
  echo "would release ${tag} (previous tag: ${prev_tag:-none})"
  echo "------------------ CHANGELOG section ------------------"
  printf '%s\n' "$new_section"
  echo "------------------------------------------------------"
  exit 0
fi

# --- preconditions ----------------------------------------------------------
branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$branch" != "main" ]; then
  echo "error: releases are cut from 'main' (currently on '$branch')." >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree is dirty; commit or stash before releasing." >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  echo "error: tag ${tag} already exists." >&2
  exit 1
fi

# Every CHANGELOG heading must be "## X.Y.Z (YYYY-MM-DD)" — no "v" prefix, no
# brackets. Keeping the changelog on the same bare X.Y.Z the appcast and bundle
# use is what stops the version-format drift that has bitten Sparkle before.
bad_headings="$(grep -nE '^## ' CHANGELOG.md \
  | grep -vE '^[0-9]+:## [0-9]+\.[0-9]+\.[0-9]+ \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$' || true)"
if [ -n "$bad_headings" ]; then
  echo "error: CHANGELOG.md has headings that are not '## X.Y.Z (YYYY-MM-DD)':" >&2
  printf '%s\n' "$bad_headings" >&2
  exit 1
fi

# --- quality gate -----------------------------------------------------------
echo "==> make test"
make test
# Build the app stamped with this exact tag, mirroring how CI builds from the
# pushed tag (VERSION = the ref name). This makes the smoke build represent the
# real release version so the bundle check below is meaningful.
echo "==> make app (VERSION=$tag)"
VERSION="$tag" make app

# The published appcast advertises sparkle:version=$VERSION (bare, no "v"). The
# bundle must stamp that SAME bare version into CFBundleVersion /
# CFBundleShortVersionString; if they disagree, Sparkle compares mismatched
# strings and offers a spurious update to the same release (the 0.2.1 bug) or
# misses a real one. Verify it here, before the tag is pushed.
app_plist="build/Aspace.app/Contents/Info.plist"
for key in CFBundleShortVersionString CFBundleVersion; do
  got="$(/usr/libexec/PlistBuddy -c "Print :$key" "$app_plist" 2>/dev/null || true)"
  if [ "$got" != "$VERSION" ]; then
    echo "error: bundle $key is '$got', expected '$VERSION' (bare X.Y.Z)." >&2
    echo "       Sparkle would compare this against the appcast's sparkle:version=$VERSION" >&2
    echo "       and mis-detect updates. Check the version stamping in Scripts/build-app.sh." >&2
    exit 1
  fi
done
echo "==> bundle version OK: CFBundleVersion=$VERSION matches the appcast"

# --- prepend the CHANGELOG section ------------------------------------------
# Insert before the first existing "## " heading so the title and intro stay on
# top. If there is no section yet, append at the end.
first_section_line="$(grep -n '^## ' CHANGELOG.md | head -n1 | cut -d: -f1 || true)"
if [ -n "$first_section_line" ]; then
  head_part="$(head -n "$((first_section_line - 1))" CHANGELOG.md)"
  tail_part="$(tail -n "+${first_section_line}" CHANGELOG.md)"
  {
    printf '%s\n\n' "$head_part"
    printf '%s\n\n' "$new_section"
    printf '%s\n' "$tail_part"
  } > CHANGELOG.md.tmp
else
  {
    cat CHANGELOG.md
    printf '\n%s\n' "$new_section"
  } > CHANGELOG.md.tmp
fi
mv CHANGELOG.md.tmp CHANGELOG.md

# --- commit, tag, push ------------------------------------------------------
git add CHANGELOG.md
if ! git commit -m "chore(release): ${tag}"; then
  echo "error: commit failed (signing agent locked?); reverting CHANGELOG so the" >&2
  echo "       tree stays clean for a retry." >&2
  git checkout -- CHANGELOG.md
  exit 1
fi
git tag -a "$tag" -m "$tag"

if $DO_PUSH; then
  git push origin HEAD
  git push origin "$tag"
  echo
  echo "released ${tag}: pushed main + tag."
  echo "CI now builds, signs, publishes the GitHub Release, and pushes the"
  echo "appcast back to main. When it finishes:  git pull --ff-only origin main"
else
  echo
  echo "prepared ${tag} locally (committed + tagged, not pushed)."
  echo "finish with:  git push origin HEAD && git push origin ${tag}"
fi
