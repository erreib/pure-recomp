#!/bin/bash
# tools/record_lap.sh TRACK            play a race by hand and log every ship's position, for a human racing line
# tools/record_lap.sh TRACK --line     turn that log into config/pad_scripts/drive/TRACK.line.csv (the follower's line)
#
# Erik drives, the sweep's follower learns the line (docs/tracks.md, "Recording a human lap"). The first form opens the
# game in a window with sound, with a copy of the player's own settings (bindings) in a scratch data directory, the
# test switches PURE_TEST_UNLOCK_ALL=1 (every track and class on the TRACK screen) and PURE_WATCH_GRID=1 (one line per
# ship per flip, from the race record array), and writes the run's log to out/laps/TRACK.log. Drive the menus to
# Single Race > the class > the league > TRACK, race three laps (the whole lap counts, not the result), then quit the
# game (close the window). The second form keeps the player's fastest whole lap as the line (tools/pp_lines.py
# --port --ships player) and writes it where the sweep reads it; the old line is kept beside it as TRACK.line.ai.csv
# the first time. Then: python3 tools/campaign_sweep.py single_race TRACK --no-damage.
set -eu
cd "$(dirname "$0")/.."
. tools/env.sh
TRACK="${1:?usage: tools/record_lap.sh TRACK [--line]}"
MODE="${2:-record}"
LOG="out/laps/$TRACK.log"
LINE="config/pad_scripts/drive/$TRACK.line.csv"
case "$MODE" in
  record)
    mkdir -p out/laps out/data/record_lap
    PLAYER="$HOME/Library/Application Support/pure-recomp/PureNative"
    [ -f "$PLAYER/settings.ini" ] && cp -f "$PLAYER/settings.ini" out/data/record_lap/settings.ini
    echo "record_lap: $TRACK: drive Single Race > class > league > $TRACK, three laps, then close the window"
    echo "record_lap: log $LOG (sound on, your bindings, every track unlocked by the test switch)"
    python3 tools/run_boot.py --window --sound --data-dir out/data/record_lap --seconds 1800 \
      --env PURE_TEST_UNLOCK_ALL=1 --env PURE_WATCH_GRID=1 --env PURE_WATCH_SHIP=1 "$LOG" || true
    n=$(grep -c "\[pure\] grid frame" "$LOG" 2>/dev/null || echo 0)
    echo "record_lap: $n grid lines in $LOG; next: tools/record_lap.sh $TRACK --line"
    ;;
  --line)
    [ -f "$LOG" ] || { echo "record_lap: no $LOG; record first"; exit 2; }
    [ -f "$LINE" ] && [ ! -f "${LINE%.csv}.ai.csv" ] && cp "$LINE" "${LINE%.csv}.ai.csv"
    python3 tools/pp_lines.py --port "$LOG" --ships player --out "$LINE" ${3:+--compare "$3"}
    echo "record_lap: wrote $LINE (the AI line kept as ${LINE%.csv}.ai.csv); try: python3 tools/campaign_sweep.py single_race $TRACK --no-damage"
    ;;
  *) sed -n '2,12p' "$0"; exit 2 ;;
esac
