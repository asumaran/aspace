#!/usr/bin/env bash
#
# logs.sh — read aspace's unified logs (subsystem com.asumaran.aspace).
#
# aspace logs every profile/resolution operation and a topology snapshot via
# os.Logger at the `.notice` level, which the unified log persists — so you can
# reproduce an issue and then read exactly what happened, no live capture
# needed. The same entries show up in Console.app (filter by the subsystem).
#
# Usage:
#   Scripts/logs.sh                      # last 5 minutes
#   Scripts/logs.sh --last 2m            # custom window (30s, 10m, 1h, ...)
#   Scripts/logs.sh --stream             # follow live
#   Scripts/logs.sh --category ProfileRunner   # one category only
#
# Categories: App, ProfileRunner, DisplayKit, Registry, CLI.
#
set -euo pipefail

SUBSYSTEM="com.asumaran.aspace"
MODE="show"
WINDOW="5m"
CATEGORY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --stream)         MODE="stream" ;;
    --last)           WINDOW="${2:?--last needs a value like 2m}"; shift ;;
    --category)       CATEGORY="${2:?--category needs a name}"; shift ;;
    -h|--help)        sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

predicate="subsystem == \"$SUBSYSTEM\""
if [ -n "$CATEGORY" ]; then
  predicate="$predicate AND category == \"$CATEGORY\""
fi

if [ "$MODE" = "stream" ]; then
  echo "streaming aspace logs (Ctrl-C to stop)..." >&2
  exec log stream --predicate "$predicate" --level info --style compact
else
  exec log show --predicate "$predicate" --last "$WINDOW" --info --style compact
fi
