#!/bin/bash
# tools/verify_task.sh NNN: runs the Verify line of docs/tasks/NNN-*.md from the repo root and prints PASS or FAIL.
set -u
cd "$(dirname "$0")/.." && . tools/env.sh
f=$(ls docs/tasks/$(printf '%03d' "${1:-0}")-*.md 2>/dev/null | head -1)
[ -n "$f" ] || { echo "no task file for $1"; exit 2; }
cmd=$(awk '/^## Verify/{f=1;next} f && /^`/{sub(/^`/,""); sub(/`$/,""); print; exit}' "$f")
[ -n "$cmd" ] || { echo "no Verify line in $f"; exit 2; }
echo "verify $1: $cmd"
bash -c "$cmd"; rc=$?
[ $rc -eq 0 ] && echo "verify $1: PASS" || echo "verify $1: FAIL (exit $rc)"
exit $rc
