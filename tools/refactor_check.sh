#!/bin/bash
# The proof that a change moved code and changed nothing on the screen (task 049; the organisation pass, M9): the
# frame regression suite's scenes captured with the build before the change and with the build after it, compared
# pixel for pixel, plus the GE backend's counts at the end of each run.
#   tools/refactor_check.sh --before [--dir DIR] [--shell headless|metal|vulkan] [--backend metal|vulkan]
#                           [--env KEY=VAL ...] [--wait SECONDS]
#   tools/refactor_check.sh [--dir DIR] [--wait SECONDS]
#   --before   captures every scene of tools/frame_regress.sh with the current build into DIR/before, and records the
#              commit, the shell, the backend and the environment in DIR/before/info.txt. Run it first, on the commit
#              the change starts from, built (tools/build.sh profile), before touching anything. It replaces earlier
#              before captures in DIR.
#   (no --before)  captures the same scenes with the current build, the shell, backend and environment the before
#              captures recorded, into DIR/after, and compares each pair with tools/imgdiff.py --tol 0 --max-frac 0.
#   --dir      default out/refactor.
#   --shell, --backend, --env  for --before only (default headless and metal: the suite's own defaults, the backend's
#              480x272 pictures, unpaced, about a minute); passed on to tools/frame_regress.sh.
#   --wait     how long the suite waits for other games to end before it starts (tools/frame_regress.sh --wait;
#              default 600, 0 gives up at once). The other worktrees' runs come and go; this one waits its turn rather
#              than fail.
# PASS (exit 0) only when every scene captured before has a capture after with 0 differing pixels, and the counts
# the backend prints at exit (the [metal] lines of each route's log, with every time and rate taken out) are the
# same; FAIL (exit 1) otherwise; exit 2 when it cannot run (no before captures, a suite refused for longer than
# --wait). The table is also written to DIR/summary.txt; the differing pixels of a failing scene to
# DIR/<scene>.diff.png, the counts that moved to DIR/counts.diff.
# Whether the suite's scenes pass against PPSSPP does not matter here (tools/frame_regress.sh says that): only that
# before and after are the same.
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh

DIR=out/refactor
MODE=after
SHELL_NAME=
BACKEND=
ENVS=()
WAIT=600
usage() {
  echo "usage: tools/refactor_check.sh [--before] [--dir DIR] [--shell headless|metal|vulkan] [--backend metal|vulkan] [--env KEY=VAL ...] [--wait SECONDS]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --before) MODE=before; shift ;;
    --dir) [ $# -ge 2 ] || usage; DIR=$2; shift 2 ;;
    --shell) [ $# -ge 2 ] || usage; SHELL_NAME=$2; shift 2 ;;
    --backend) [ $# -ge 2 ] || usage; BACKEND=$2; shift 2 ;;
    --env) [ $# -ge 2 ] || usage; case $2 in *=*) ;; *) usage ;; esac; ENVS+=("$2"); shift 2 ;;
    --wait) [ $# -ge 2 ] || usage; WAIT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "refactor_check: unknown argument $1"; usage ;;
  esac
done
case $WAIT in ''|*[!0-9]*) echo "refactor_check: --wait takes seconds, not $WAIT"; exit 2 ;; esac
mkdir -p "$DIR"
DIR=$(cd "$DIR" && pwd)
INFO="$DIR/before/info.txt"

if [ $MODE = before ]; then
  SHELL_NAME=${SHELL_NAME:-headless}
  BACKEND=${BACKEND:-metal}
else
  if [ -n "$SHELL_NAME$BACKEND" ] || [ ${#ENVS[@]} -gt 0 ]; then
    echo "refactor_check: --shell, --backend and --env go with --before; the after captures take the before's"
    exit 2
  fi
  [ -f "$INFO" ] || { echo "refactor_check: no before captures in $DIR/before (tools/refactor_check.sh --before, on the starting commit)"; exit 2; }
  SHELL_NAME=$(sed -n 's/^shell=//p' "$INFO")
  BACKEND=$(sed -n 's/^backend=//p' "$INFO")
  while IFS= read -r e; do ENVS+=("$e"); done < <(sed -n 's/^env=//p' "$INFO")
fi

commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
git diff --quiet HEAD 2>/dev/null || commit="$commit+changes"

# capture WHERE: the suite's scenes with the current build into WHERE/run (tools/frame_regress.sh --out), the suite
# waiting up to --wait seconds for another game (tools/frame_regress.sh --wait).
capture() {
  local where=$1 rc
  local args=(--wait "$WAIT" --out "$where/run" --shell "$SHELL_NAME" --backend "$BACKEND")
  local e
  for e in ${ENVS[@]+"${ENVS[@]}"}; do args+=(--env "$e"); done
  tools/frame_regress.sh "${args[@]}" > "$where/frame_regress.stdout" 2>&1
  rc=$?
  grep -E '^frame_regress: (waiting|.*free after)' "$where/frame_regress.stdout" | sed 's/^frame_regress: /  /'
  if [ $rc -eq 2 ]; then
    cat "$where/frame_regress.stdout"
    echo "refactor_check: tools/frame_regress.sh could not run"
    exit 2
  fi
  grep -E '^run |^frame regression:' "$where/frame_regress.stdout" | sed 's/^/  /'
}

# counts LOG: the backend's [metal] lines printed at exit and every 600 frames, with what depends on the machine's
# speed taken out (times and rates; the GPU waits, which depend on when the GPU finishes; and of the pipelines, which
# of them a draw made or took from the pre-warm, which depends on when Metal's threads finished the pre-warm), and
# without the start-up lines (the device, the compile time, the pre-warm's path and time). The exit line has gone on
# past the GPU waits since E7 (`...; N textures upscaled (T ms)`): the waits are taken out wherever they stand and the
# upscale's time with them (task 094; anchored at the line's end, the filter had left both in, so every run FAILed).
counts() {
  grep -E '^\[metal\] ' "$1" |
    grep -Ev '^\[metal\] (drawing with|pre-warm|frame trace)' |
    sed -E 's/ \([0-9.e+-]+ ms waited\)//g; s/, [0-9]+ GPU waits \([0-9.e+-]+ ms\) in [0-9.e+-]+ s(;|$)/\1/;
            s/ textures upscaled \([0-9.e+-]+ ms\)/ textures upscaled/;
            s/, [0-9.e+-]+ fps\)/)/;
            s/, [0-9]+ made by a draw \([0-9]+ of them waited for the pre-warm, ([0-9]+) not in the list\), [0-9]+ taken from the pre-warm of ([0-9]+)/, \1 not in the pre-warm list of \2/'
}

if [ $MODE = before ]; then
  rm -rf "$DIR/before" "$DIR/after"
  rm -f "$DIR"/*.diff.png "$DIR/counts.diff" "$DIR/summary.txt"
  mkdir -p "$DIR/before"
  echo "refactor_check: before captures, commit $commit, shell $SHELL_NAME, backend $BACKEND, into $DIR/before"
  t0=$SECONDS
  capture "$DIR/before"
  shots=$(ls "$DIR/before/run/shots/"*.png 2>/dev/null | wc -l | tr -d ' ')
  {
    echo "commit=$commit"
    echo "date=$(date '+%Y-%m-%d %H:%M')"
    echo "shell=$SHELL_NAME"
    echo "backend=$BACKEND"
    for e in ${ENVS[@]+"${ENVS[@]}"}; do echo "env=$e"; done
  } > "$INFO"
  echo "refactor_check: $shots scenes captured before ($((SECONDS - t0)) s); after the change: tools/refactor_check.sh"
  [ "$shots" -gt 0 ]
  exit
fi

rm -rf "$DIR/after"
rm -f "$DIR"/*.diff.png "$DIR/counts.diff" "$DIR/summary.txt"
mkdir -p "$DIR/after"
START=$SECONDS
SUMMARY=()
note() { echo "$*"; SUMMARY+=("$*"); }
note "refactor check $(date '+%Y-%m-%d %H:%M'): before commit $(sed -n 's/^commit=//p' "$INFO") ($(sed -n 's/^date=//p' "$INFO")), after commit $commit"
note "shell $SHELL_NAME, backend $BACKEND, extra environment: ${ENVS[*]:-none}"
capture "$DIR/after"

row() { printf '%-18s %10s  %s' "$@"; }
note ""
note "$(row scene differing result)"
PASSED=0
TOTAL=0
for before in "$DIR/before/run/shots/"*.png; do
  [ -f "$before" ] || continue
  scene=$(basename "$before" .png)
  TOTAL=$((TOTAL + 1))
  after="$DIR/after/run/shots/$scene.png"
  differing=-
  if [ ! -f "$after" ]; then
    result="FAIL (no capture after)"
  else
    line=$(python3 tools/imgdiff.py "$after" "$before" --tol 0 --max-frac 0 --out "$DIR/$scene.diff.png" 2>&1)
    rc=$?
    differing=$(echo "$line" | sed -n 's/.*(\([0-9]*\)\/[0-9]* pixels differ.*/\1/p')
    if [ $rc -eq 0 ]; then
      result=PASS; PASSED=$((PASSED + 1)); rm -f "$DIR/$scene.diff.png"
    elif [ $rc -eq 1 ]; then
      result="FAIL (diff $DIR/$scene.diff.png)"
    else
      result="ERROR ($line)"; rm -f "$DIR/$scene.diff.png"
    fi
  fi
  note "$(row "$scene" "${differing:--}" "$result")"
done

# The counts, route by route.
COUNTS=PASS
: > "$DIR/counts.diff"
for log in "$DIR/after/run/"*.log; do
  [ -f "$log" ] || continue
  name=$(basename "$log" .log)
  counts "$log" > "${log%.log}.counts"
  if [ -f "$DIR/before/run/$name.log" ]; then
    counts "$DIR/before/run/$name.log" > "$DIR/before/run/$name.counts"
  else
    echo "no before log for $name" > "$DIR/before/run/$name.counts"
  fi
  if ! diff "$DIR/before/run/$name.counts" "${log%.log}.counts" >> "$DIR/counts.diff" 2>&1; then
    COUNTS=FAIL
  fi
done
lines=$(cat "$DIR/after/run/"*.counts 2>/dev/null | wc -l | tr -d ' ')
[ "$lines" -gt 0 ] || COUNTS=FAIL
note ""
if [ $COUNTS = PASS ]; then
  note "counts: the same in every route ($lines [metal] lines)"
  rm -f "$DIR/counts.diff"
else
  note "counts: FAIL ($lines [metal] lines after; what moved is in $DIR/counts.diff)"
fi
verdict=FAIL
[ $TOTAL -gt 0 ] && [ $PASSED -eq $TOTAL ] && [ $COUNTS = PASS ] && verdict=PASS
note "refactor check: $verdict, $PASSED/$TOTAL scenes with 0 differing pixels, counts $COUNTS ($(( (SECONDS - START) / 60 ))m $(( (SECONDS - START) % 60 ))s)"
printf '%s\n' "${SUMMARY[@]}" > "$DIR/summary.txt"
[ "$verdict" = PASS ]
