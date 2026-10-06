#!/bin/bash
# The save round trip of M5 (task 014): three windowed runs on a memory stick of their own (PURE_GAME_DIR=out/014/game,
# EBOOT.ELF and disc.iso linked from game/), so the checkout's game/ms0 is never touched.
#   1. NEW   empty ms0, config/pad_scripts/main_menu.txt (profile NAME0000, tag AAA, save question YES): the game's
#            LISTSAVE writes UCUS98612P0000 with PARAM.SFO, PROFILE.BIN and ICON0.PNG; PARAM.SFO names the folder and
#            the pilot; MAIN MENU is reached. A capture of SET NAME on the empty stick ("NAME") is the control.
#   2. LOAD  config/pad_scripts/profile_load.txt on that stick: LISTLOAD loads P0000, MAIN MENU matches run 1's,
#            the game's own PROFILE > SAVE writes the loaded profile back (LISTSAVE), and SET NAME shows the loaded
#            name ("NAME0000": region variance on the digits, which are blank on the control).
#   3. DLC   run 2 again with an empty sibling UCUS98612DGAMMAPACK1 (a download-pack folder without PI.WAD): the
#            game's SAVEDATA scan sees it, the profile still loads and shows, and the run reaches its last frame.
# Exit 0 only when all three hold. Logs, captures and the stick stay in out/014/. About 7 minutes: input scripts need
# the renderer's pad, so every run is windowed. The runs are silent and use the data directory
# out/data/save_roundtrip (settings.ini, save backups), not the player's, unless the environment sets PURE_NO_AUDIO or
# PURE_DATA_DIR (tools/run_boot.py; task 034).
#   tools/save_roundtrip.sh
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
OUT=out/014
GAME=$OUT/game
SAVE=$GAME/ms0/PSP/SAVEDATA
FOLDER=UCUS98612P0000
NAME=NAME0000
DLC=UCUS98612DGAMMAPACK1
DIGITS=200,92,115,26   # PSP pixels: the 5th to 8th letters of the SET NAME field, blank for the default "NAME"
MIN_NAME_VARIANCE=500  # measured: 1545 with NAME0000 loaded, 0 on the empty stick

[ -x build/arm64/bin/PureNative ] || { echo "build/arm64/bin/PureNative missing: tools/build.sh profile"; exit 2; }
[ -f game/EBOOT.ELF ] || { echo "game/EBOOT.ELF missing: tools/setup_game.sh"; exit 2; }
[ -e game/disc.iso ] || { echo "game/disc.iso dangles; stop here, do not look for the image elsewhere"; exit 2; }

mkdir -p "$GAME"
ln -sfn "$ROOT/game/EBOOT.ELF" "$GAME/EBOOT.ELF"
ln -sfn "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' game/disc.iso)" "$GAME/disc.iso"
rm -rf "$GAME/ms0" "$OUT"/run1 "$OUT"/run2 "$OUT"/run3
mkdir -p "$SAVE"

FAILS=0
ok()   { echo "  ok    $*"; }
bad()  { echo "  FAIL  $*"; FAILS=$((FAILS + 1)); }

# run NAME SCRIPT FRAMES [--env K=V ...]: one bounded windowed run, log in out/014/NAME.log, captures in out/014/NAME/.
run() {
  local name=$1 script=$2 frames=$3; shift 3
  echo "$name: $(basename "$script"), $frames frames"
  python3 tools/run_boot.py --script "$script" --shots "$OUT/$name" --frames "$frames" --seconds 400 \
    --data-dir out/data/save_roundtrip \
    --env PURE_GAME_DIR="$ROOT/$GAME" --env PURE_TRACE_SAVEDATA=1 "$@" "$OUT/$name.log" > "$OUT/$name.stdout" 2>&1
  local rc=$?
  if [ $rc -eq 0 ] && grep -q "^\[pure\] exit at frame $frames" "$OUT/$name.log"; then
    ok "reached frame $frames (run_boot exit 0)"
  else
    bad "run ended early or hung (run_boot exit $rc; last lines in $OUT/$name.stdout)"
  fi
}

# variance PNG REGION: the largest per-channel variance inside REGION (PSP pixels), -1 when the capture is missing.
variance() {
  [ -f "$1" ] || { echo -1; return; }
  python3 tools/imgdiff.py "$1" --min-variance 0 --region "$2" --json |
    python3 -c 'import json, sys; print(int(json.load(sys.stdin)["max_variance"]))'
}

# folder_check: the save folder's PSP layout, its PARAM.SFO and the pilot in PROFILE.BIN. Exit code = failures.
folder_check() {
  python3 - "$SAVE/$FOLDER" "$FOLDER" "$NAME" <<'EOF'
import os, struct, sys
folder, expect_dir, expect_name = sys.argv[1:4]
fails = 0
def ok(m): print("  ok    " + m)
def bad(m):
    global fails
    fails += 1
    print("  FAIL  " + m)
if not os.path.isdir(folder):
    bad(f"{folder} does not exist"); sys.exit(fails)
files = sorted(os.listdir(folder))
print("        " + os.path.basename(folder) + ": " + ", ".join(f"{f} {os.path.getsize(os.path.join(folder, f))}" for f in files))
for f in ("PARAM.SFO", "PROFILE.BIN", "ICON0.PNG"):
    (ok if f in files else bad)(f"{f} present")
if "PARAM.SFO" not in files:
    print("  ESCALATE: the save folder lacks PARAM.SFO (framework bug: report, do not patch)")
    sys.exit(fails)
data = open(os.path.join(folder, "PARAM.SFO"), "rb").read()
sfo = {}
if data[:4] == b"\0PSF":
    keys, values, count = struct.unpack_from("<III", data, 8)
    for i in range(count):
        koff, fmt, length, _, voff = struct.unpack_from("<HHIII", data, 20 + i * 16)
        key = data[keys + koff:data.index(b"\0", keys + koff)].decode()
        raw = data[values + voff:values + voff + length]
        if fmt == 0x0404:
            sfo[key] = struct.unpack("<I", raw)[0]
        elif key in ("SAVEDATA_FILE_LIST", "SAVEDATA_PARAMS"):
            sfo[key] = raw   # binary
        else:
            sfo[key] = raw.split(b"\0")[0].decode("latin-1")
else:
    bad("PARAM.SFO has no PSF header")
for key in ("TITLE", "SAVEDATA_TITLE", "SAVEDATA_DIRECTORY"):
    print(f"        {key} = {sfo.get(key)!r}")
print("        SAVEDATA_DETAIL = " + repr(sfo.get("SAVEDATA_DETAIL", "")))
(ok if sfo.get("SAVEDATA_DIRECTORY") == expect_dir else bad)(f"PARAM.SFO SAVEDATA_DIRECTORY is {expect_dir}")
(ok if f"User name: {expect_name}" in str(sfo.get("SAVEDATA_DETAIL", "")) else bad)(f"PARAM.SFO detail names the pilot {expect_name}")
# SAVEDATA_FILE_LIST names encrypted files only. The game's request is 0x5DC bytes (no key field), so its saves
# are plain and the list stays empty; PROFILE.BIN is checked as plaintext below.
listed = sfo.get("SAVEDATA_FILE_LIST", b"")
listed = [listed[i:i + 13].split(b"\0")[0].decode("latin-1") for i in range(0, len(listed), 32) if listed[i:i + 1] not in (b"", b"\0")]
print("        SAVEDATA_FILE_LIST = " + (", ".join(listed) if listed else "empty (plain save)"))
if "PROFILE.BIN" in files:
    prof = open(os.path.join(folder, "PROFILE.BIN"), "rb").read()
    name = prof[4:15].split(b"\0")[0].decode("latin-1").strip()
    tag = prof[15:19].split(b"\0")[0].decode("latin-1")
    (ok if name == expect_name else bad)(f"PROFILE.BIN holds pilot {name!r}, tag {tag!r}")
sys.exit(fails)
EOF
  FAILS=$((FAILS + $?))
}

declare -a OUTCOME

# 1. NEW on an empty stick.
FAILS=0
cat config/pad_scripts/main_menu.txt > "$OUT/run1-route.txt"
echo "2250:shot fresh-name" >> "$OUT/run1-route.txt"
run run1 "$OUT/run1-route.txt" 4800
if grep -q "^\[savedata\] LISTSAVE (5) game=\"UCUS98612\"" "$OUT/run1.log" &&
   grep -q "^\[savedata\] saved [0-9]* bytes to .*/$FOLDER\$" "$OUT/run1.log"; then
  ok "$(grep -m1 "^\[savedata\] saved [0-9]* bytes to .*/$FOLDER\$" "$OUT/run1.log" | sed "s|$ROOT/||")"
else
  bad "no LISTSAVE into $FOLDER in $OUT/run1.log"
fi
folder_check
v_fresh=$(variance "$OUT/run1/fresh-name.png" "$DIGITS")
if [ "$v_fresh" -ge 0 ] && [ "$v_fresh" -lt 50 ]; then ok "control: SET NAME on the empty stick is blank past NAME (variance $v_fresh)"
else bad "control capture $OUT/run1/fresh-name.png: variance $v_fresh (want 0 to 49; did the route timing move?)"; fi
[ -f "$OUT/run1/menu.png" ] && ok "MAIN MENU captured ($OUT/run1/menu.png)" || bad "no MAIN MENU capture"
mtime1=$(stat -f %m "$SAVE/$FOLDER/PROFILE.BIN" 2>/dev/null || echo 0)
verdict() { [ $FAILS -eq 0 ] && echo "PASS: $1" || echo "FAIL ($FAILS checks, see above)"; }
OUTCOME[1]="run 1 NEW (main_menu.txt, empty stick): $(verdict "LISTSAVE wrote $FOLDER with PARAM.SFO, PROFILE.BIN (pilot $NAME) and ICON0.PNG; MAIN MENU reached")"
TOTAL=$FAILS

# 2 and 3: LOAD, then the profile's own SAVE, then SET NAME.
load_checks() {
  local name=$1
  if grep -q "^\[savedata\] LISTLOAD (4) game=\"UCUS98612\"" "$OUT/$name.log" &&
     grep -q "^\[savedata\] loaded [0-9]* bytes from .*/$FOLDER\$" "$OUT/$name.log"; then
    ok "$(grep -m1 "^\[savedata\] loaded [0-9]* bytes from .*/$FOLDER\$" "$OUT/$name.log" | sed "s|$ROOT/||")"
  else
    bad "no LISTLOAD of $FOLDER in $OUT/$name.log"
    grep "^\[savedata\]" "$OUT/$name.log" | head -20
  fi
  local l_load l_save
  l_load=$(grep -n -m1 "^\[savedata\] loaded" "$OUT/$name.log" | cut -d: -f1)
  l_save=$(grep -n "^\[savedata\] saved [0-9]* bytes to .*/$FOLDER\$" "$OUT/$name.log" | tail -1 | cut -d: -f1)
  if [ -n "$l_load" ] && [ -n "$l_save" ] && [ "$l_save" -gt "$l_load" ]; then
    ok "the game's own PROFILE > SAVE wrote the loaded profile back (LISTSAVE into $FOLDER)"
  else
    bad "no LISTSAVE into $FOLDER after the load"
  fi
  if python3 tools/imgdiff.py "$OUT/$name/menu-loaded.png" "$OUT/run1/menu.png" --tol 32 --max-frac 0.01 > "$OUT/$name.menu.txt" 2>&1; then
    ok "MAIN MENU after LOAD matches run 1's ($(cut -d' ' -f1-3 "$OUT/$name.menu.txt"))"
  else
    bad "MAIN MENU after LOAD: $(head -1 "$OUT/$name.menu.txt")"
  fi
  v=$(variance "$OUT/$name/name-loaded.png" "$DIGITS")
  if [ "$v" -ge "$MIN_NAME_VARIANCE" ]; then ok "SET NAME shows the loaded name past NAME (variance $v >= $MIN_NAME_VARIANCE; control $v_fresh)"
  else bad "SET NAME capture $OUT/$name/name-loaded.png: variance $v < $MIN_NAME_VARIANCE"; fi
  folder_check
}

FAILS=0
run run2 config/pad_scripts/profile_load.txt 3900
load_checks run2
mtime2=$(stat -f %m "$SAVE/$FOLDER/PROFILE.BIN" 2>/dev/null || echo 0)
[ "$mtime2" -gt "$mtime1" ] && ok "PROFILE.BIN rewritten during run 2" || bad "PROFILE.BIN not rewritten during run 2"
OUTCOME[2]="run 2 LOAD (profile_load.txt): $(verdict "LISTLOAD loaded $FOLDER, MAIN MENU as in run 1, PROFILE > SAVE rewrote it, SET NAME shows $NAME (variance $v; empty stick $v_fresh)")"
TOTAL=$((TOTAL + FAILS))

# 3. The DLC door: an empty download-pack folder beside the profile.
FAILS=0
mkdir -p "$SAVE/$DLC"
run run3 config/pad_scripts/profile_load.txt 3900 --env PURE_TRACE_IO=1
if grep -q "^\[io\] dread ms0:/PSP/SAVEDATA/* -> $DLC" "$OUT/run3.log"; then
  ok "the game's SAVEDATA scan saw $DLC"
else
  bad "no SAVEDATA scan saw $DLC (PURE_TRACE_IO in $OUT/run3.log)"
fi
touched=$(grep "$DLC" "$OUT/run3.log" | grep -v '\] dread ' | head -5)
[ -n "$touched" ] && echo "        other accesses: $touched" || echo "        no access to $DLC beyond the directory scan"
dlc_note="no PI.WAD open seen"
grep -q "open ms0:/PSP/SAVEDATA/$DLC/PI.WAD .*-> 0x80010002" "$OUT/run3.log" &&
  dlc_note="its PI.WAD open fails (0x80010002, no such file) and the game moves on"
load_checks run3
[ -d "$SAVE/$DLC" ] && [ -z "$(ls -A "$SAVE/$DLC")" ] && ok "$DLC left as it was (empty)" || bad "$DLC changed"
OUTCOME[3]="run 3 DLC door (+ empty $DLC): $(verdict "seen by the SAVEDATA scan, $dlc_note; profile loaded, saved and shown (variance $v); last frame reached")"
TOTAL=$((TOTAL + FAILS))

echo
for i in 1 2 3; do echo "${OUTCOME[$i]}"; done
if [ $TOTAL -eq 0 ]; then echo "save round trip: PASS"; exit 0; fi
echo "save round trip: FAIL ($TOTAL checks)"; exit 1
