#!/bin/bash
# The save round trip of M5 (task 014): three windowed runs on a memory stick of their own (PURE_GAME_DIR=out/014/game,
# EBOOT.ELF and disc.iso linked from game/), so the checkout's game/ms0 is never touched.
#   1. NEW   empty ms0, config/pad_scripts/main_menu.txt (profile NAME0000, tag AAA, save question YES): the game's
#            LISTSAVE writes UCUS98612P0000 with PARAM.SFO, PROFILE.BIN and ICON0.PNG; PARAM.SFO names the folder and
#            the pilot; MAIN MENU is reached. A capture of SET NAME on the empty stick ("NAME") is the control.
#   2. LOAD  config/pad_scripts/profile_load.txt on that stick: LISTLOAD loads P0000, MAIN MENU matches run 1's,
#            the game's own PROFILE > SAVE writes the loaded profile back (LISTSAVE, answered by the route's
#            `save P0000`, where a player would pick the profile's slot in the save list), and SET NAME shows the
#            loaded name ("NAME0000": region variance on the digits, which are blank on the control).
#   3. DLC   run 2 again with an empty sibling UCUS98612DGAMMAPACK1 (a download-pack folder without PI.WAD): the
#            game's SAVEDATA scan sees it, the profile still loads and shows, and the run reaches its last frame.
#   4. TWO   a second profile on the same stick (config/pad_scripts/two_profiles.txt, task 039): PROFILE > NEW makes
#            NAME1111 and the game's LISTSAVE opens the save list (P0000 beside four free slots) on the first free
#            slot; Cross saves UCUS98612P0001 and P0000 is not written; PROFILE > LOAD lists both, Up and Cross load
#            P0000, and SET NAME shows NAME0000 again.
#   5. LIST  a restart (config/pad_scripts/profile_list_load.txt): the boot LOAD lists both profiles on the newest,
#            P0001; Cross loads it and SET NAME shows NAME1111. Both folders hold their own pilots.
# Exit 0 only when all five hold. Logs, captures and the stick stay in out/014/ (the save list's captures in
# out/014/run4/ and run5/). About 13 minutes: input scripts need the renderer's pad, so every run is windowed. The runs are silent and use the data directory
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
SECOND=UCUS98612P0001   # task 039: the second profile, which the save list puts in the first free slot
SECOND_NAME=NAME1111
DLC=UCUS98612DGAMMAPACK1
DIGITS=200,92,115,26   # PSP pixels: the 5th to 8th letters of the SET NAME field, blank for the default "NAME"
MIN_NAME_VARIANCE=500  # measured: 1545 with NAME0000 loaded, 0 on the empty stick

[ -x build/arm64/bin/PureNative ] || { echo "build/arm64/bin/PureNative missing: tools/build.sh profile"; exit 2; }
[ -f game/EBOOT.ELF ] || { echo "game/EBOOT.ELF missing: tools/setup_game.sh"; exit 2; }
[ -e game/disc.iso ] || { echo "game/disc.iso dangles; stop here, do not look for the image elsewhere"; exit 2; }

mkdir -p "$GAME"
ln -sfn "$ROOT/game/EBOOT.ELF" "$GAME/EBOOT.ELF"
ln -sfn "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' game/disc.iso)" "$GAME/disc.iso"
rm -rf "$GAME/ms0" "$OUT"/run1 "$OUT"/run2 "$OUT"/run3 "$OUT"/run4 "$OUT"/run5
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

# folder_check [FOLDER PILOT]: the save folder's PSP layout, its PARAM.SFO and the pilot in PROFILE.BIN (default
# $FOLDER, $NAME). Exit code = failures.
folder_check() {
  local folder=${1:-$FOLDER} pilot=${2:-$NAME}
  python3 - "$SAVE/$folder" "$folder" "$pilot" <<'EOF'
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

# 4. A second profile, through the save list (task 039).
FAILS=0
mtime_first=$(stat -f %m "$SAVE/$FOLDER/PROFILE.BIN" 2>/dev/null || echo 0)
run run4 config/pad_scripts/two_profiles.txt 6450
if grep -q "^\[savedata\] LISTSAVE: the save list is open (5 entries)" "$OUT/run4.log" &&
   grep -q "^\[ui\] save list open: Save, 5 entries, on P0001" "$OUT/run4.log"; then
  ok "the second profile's LISTSAVE opened the save list on the first free slot, P0001"
else
  bad "no save list for the second profile's LISTSAVE in $OUT/run4.log"
  grep "^\[savedata\]\|^\[ui\]" "$OUT/run4.log" | grep -v "status [0-4]$" | tail -12
fi
if grep -q "^\[savedata\] saved [0-9]* bytes to .*/$SECOND\$" "$OUT/run4.log"; then
  ok "Cross on the free slot saved $SECOND"
else
  bad "no save into $SECOND in $OUT/run4.log"
fi
if grep -q "^\[savedata\] saved [0-9]* bytes to .*/$FOLDER\$" "$OUT/run4.log" ||
   [ "$(stat -f %m "$SAVE/$FOLDER/PROFILE.BIN" 2>/dev/null || echo 0)" != "$mtime_first" ]; then
  bad "$FOLDER was written during run 4 (the second profile overwrote the first)"
else
  ok "$FOLDER not written by the second profile"
fi
if grep -q "^\[savedata\] LISTLOAD: the save list is open (2 entries)" "$OUT/run4.log" &&
   grep -q "^\[savedata\] loaded [0-9]* bytes from .*/$FOLDER\$" "$OUT/run4.log"; then
  ok "PROFILE > LOAD listed both saves and Up + Cross loaded $FOLDER"
else
  bad "no LISTLOAD list or no load of $FOLDER in $OUT/run4.log"
fi
for shot in list-save save-completed list-load list-load-p0000; do
  [ -f "$OUT/run4/$shot.png" ] && ok "captured $OUT/run4/$shot.png" || bad "no capture $OUT/run4/$shot.png"
done
if python3 tools/imgdiff.py "$OUT/run4/name-p0000.png" "$OUT/run2/name-loaded.png" --region "$DIGITS" --tol 32 \
     --max-frac 0.05 > "$OUT/run4.name.txt" 2>&1; then
  ok "SET NAME after loading $FOLDER from the list shows $NAME, as run 2's ($(cut -d' ' -f1-3 "$OUT/run4.name.txt"))"
else
  bad "SET NAME after the list's load: $(head -1 "$OUT/run4.name.txt")"
fi
folder_check "$FOLDER" "$NAME"
folder_check "$SECOND" "$SECOND_NAME"
OUTCOME[4]="run 4 second profile (two_profiles.txt): $(verdict "the save list put $SECOND_NAME in $SECOND, $FOLDER kept $NAME; LOAD listed both and loaded $FOLDER by choice")"
TOTAL=$((TOTAL + FAILS))

# 5. Restart and LOAD: the list of both, on the newest.
FAILS=0
run run5 config/pad_scripts/profile_list_load.txt 3400
if grep -q "^\[ui\] save list open: Load, 2 entries, on P0001" "$OUT/run5.log" &&
   grep -q "^\[savedata\] loaded [0-9]* bytes from .*/$SECOND\$" "$OUT/run5.log"; then
  ok "the boot LOAD listed both profiles on the newest, P0001, and Cross loaded $SECOND"
else
  bad "no LISTLOAD list on P0001 or no load of $SECOND in $OUT/run5.log"
  grep "^\[savedata\]\|^\[ui\]" "$OUT/run5.log" | grep -v "status [0-4]$" | tail -12
fi
[ -f "$OUT/run5/list-boot.png" ] && ok "captured $OUT/run5/list-boot.png" || bad "no capture $OUT/run5/list-boot.png"
v5=$(variance "$OUT/run5/name-p0001.png" "$DIGITS")
python3 tools/imgdiff.py "$OUT/run5/name-p0001.png" "$OUT/run2/name-loaded.png" --region "$DIGITS" --tol 32 \
  --max-frac 0.05 > "$OUT/run5.name.txt" 2>&1
differs=$?
if [ "$v5" -ge "$MIN_NAME_VARIANCE" ] && [ $differs -eq 1 ]; then
  ok "SET NAME shows a loaded name other than $NAME (variance $v5; against run 2's: $(cut -d' ' -f1-3 "$OUT/run5.name.txt"))"
else
  bad "SET NAME capture $OUT/run5/name-p0001.png: variance $v5, against run 2's $NAME: $(head -1 "$OUT/run5.name.txt")"
fi
folder_check "$FOLDER" "$NAME"
folder_check "$SECOND" "$SECOND_NAME"
OUTCOME[5]="run 5 restart LOAD (profile_list_load.txt): $(verdict "the list showed both on the newest; $SECOND ($SECOND_NAME) loaded and shown (variance $v5); both folders hold their own pilots")"
TOTAL=$((TOTAL + FAILS))

echo
for i in 1 2 3 4 5; do echo "${OUTCOME[$i]}"; done
if [ $TOTAL -eq 0 ]; then echo "save round trip: PASS"; exit 0; fi
echo "save round trip: FAIL ($TOTAL checks)"; exit 1
