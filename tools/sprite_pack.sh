#!/bin/bash
# The upscaled art as a texture pack for the Vulkan renderer (task 074, E7, D-018 point 4). With PURE_SPRITE_DUMP=DIR
# the Metal backend writes each texture it upscales (task 073) also as an entry of a PPSSPP-format pack, DIR/pack:
# <key>.png (the 4x picture) and the line `<key> = <key>.png` under textures.ini's [hashes], the key the framework's
# pack loader computes for the same texture (hash xxh64, ignoreAddress; src/gpu/metal_textures.mm, docs/metal-backend.md
# "Sprite upscale"). This tool builds the pack from the routes that visit every menu and HUD, and checks it in the
# Vulkan window. The pack holds the game's art: it stays under out/ and is never committed.
#   tools/sprite_pack.sh [--out DIR] [--check] [--pack DIR] [--wait SECONDS]
#   --out    default out/sprite_pack: DIR/pack the pack (textures.ini and the PNGs), DIR/dump the dump's own files
#            (task 073's <key>.src.png and <key>.png), DIR/regress and DIR/sweep the build's runs, DIR/check the check's
#            runs (off/ and on/) and its data directory, DIR/summary.txt what was printed.
#   --check  the check below, after the build (or of --pack's folder, without a build).
#   --pack   check this pack folder instead of building one (implies --check). The only mode on Windows, which has no
#            Metal backend to build with: the rig gets the pack as a folder copied from the Mac. Any PPSSPP-format pack
#            of PNG or ZIM images (task 099: the HD pack of D-024, given by its folder, never copied into the repository).
#   --wait   how long to wait for other games to end before each run (tools/frame_regress.sh --wait, and
#            tools/lib.sh's wait_game before a sweep; default 600, 0 gives up at once).
# The build (macOS), headless on the Metal backend with PURE_SPRITE_UPSCALE=1 and PURE_SPRITE_DUMP=DIR/dump (the
# dump collects across runs into one folder; a key already in it is skipped):
#   - the frame regression suite's 18 scenes' routes (tools/frame_regress.sh --out DIR/regress): the frontend, the main
#     menu, and the Single Race, Time Trial, Free Play, Tournament and Zone menus to the first HUD frame of each race;
#   - the race routes on to their results screens, which the suite's routes stop before: RACE_CELLS, each a
#     tools/campaign_sweep.py cell with --no-damage (out to DIR/sweep, the race paced, about 3.5 minutes each). Each
#     added two small CLUT4 32x16 pictures on 2026-10-11; a Zone cell to its end panel added none and is not run, and
#     Free Play's session end and the Tournament's standings (four races) are not run.
#   DIR/dump/pack then moves to DIR/pack. Prints the keys each route added, the pack's keys and its size.
# The check (--check), on either system: the pack read as the loader reads it (textures.ini's [options] and [hashes],
# the files it names counted, and those missing); then a data directory of its own, DIR/check/data (a fresh scratch one, as
# tools/purelib/port.py makes them), with the pack copied in at textures/UCUS98612, where the Vulkan renderer looks
# for an installed pack; and the scenes main_menu and race_hud captured in the Vulkan window (tools/frame_regress.sh
# --shell vulkan --backend vulkan --only main_menu,race_hud: each run unpaced until 300 flips before its scene, paced
# from there) twice, into DIR/check/off with PURE_TEXTURE_PACK=0 (video.texture_pack off: the originals) and into
# DIR/check/on with PURE_TEXTURE_PACK=1 and PURE_TRACE_TEXTURE_PACK=1 (every lookup, decode and upload logged).
# PASS when:
#   - the pack holds at least 40 keys, and not every file its [hashes] name is missing (the count of missing files and
#     the first three are printed: the HD pack names 2549 files it does not hold and still replaces);
#   - each run with the pack logged `[texpack] N textures from <data>/textures/UCUS98612` with N the pack's keys (the
#     framework opened it: TexturePack::open);
#   - the runs with the pack drew replacements: at least 10 distinct images of the pack uploaded
#     (`[texpack] frame F: uploaded NAME`, a .png or a .zim, which happens when a draw first samples it), and draws
#     replaced on each route; per route the keys the lookups found, the images decoded (`[texpack] decoded NAME`) and
#     uploaded, the draws replaced and the peak of the budget line (`M images on the GPU (K MB)`) are printed;
#   - no image the pack holds was refused: a `[texpack] cannot use NAME: REASON` other than "missing or unreadable"
#     (a file the ini names that the pack lacks, which is counted) fails the check;
#   - each scene's capture with the pack differs from the one without in at least 1% of its pixels at tol 24;
#   - for a pack of the game's own art (every [hashes] entry `<key> = <key>.png`, what the build above writes), each
#     capture with the pack, reduced to 480x272 by the centre pixel of each S x S block (S its width over 480: the
#     Vulkan window's captures are the window's pixels, 960x544 in the default window, S 2), is within the scene's
#     limit of its reference at the scene's tol, both read from tools/frame_regress.sh's table (the capture without the
#     pack reduced the same way is printed beside it); for any other pack (new art, such as the HD pack) the figure is
#     printed and is not a rule;
#   - race_hud's capture with the pack passes tools/hud_check.py (the HUD found).
# Prints the table and `sprite_pack: PASS` or `FAIL` last. Exit 0 PASS (or a build without --check that made a pack),
# 1 FAIL, 2 cannot run (a run refused for longer than --wait, no Metal to build with, no pack).
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh
. tools/lib.sh

DIR=out/sprite_pack
CHECK=no
PACK=
WAIT=600
# The race routes to their results screens: tools/campaign_sweep.py MODE TRACK, with --no-damage.
RACE_CELLS="single_race:vineta_k time_trial:vineta_k"
CHECK_SCENES="main_menu race_hud"
HUD_SCENES="race_hud"
GAME_ID=UCUS98612
WINDOWS=
case "$(uname -s)" in MINGW*|MSYS*) WINDOWS=1 ;; esac
usage() {
  echo "usage: tools/sprite_pack.sh [--out DIR] [--check] [--pack DIR] [--wait SECONDS]"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --out) [ $# -ge 2 ] || usage; DIR=$2; shift 2 ;;
    --check) CHECK=yes; shift ;;
    --pack) [ $# -ge 2 ] || usage; PACK=$2; CHECK=yes; shift 2 ;;
    --wait) [ $# -ge 2 ] || usage; WAIT=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "sprite_pack: unknown argument $1"; usage ;;
  esac
done
case $WAIT in ''|*[!0-9]*) echo "sprite_pack: --wait takes seconds, not $WAIT"; exit 2 ;; esac
if [ -n "$WINDOWS" ] && [ -z "$PACK" ]; then
  echo "sprite_pack: nothing to build on Windows (the pack comes from the Metal backend): copy out/sprite_pack/pack"
  echo "from the Mac and run tools/sprite_pack.sh --check --pack DIR"
  exit 2
fi
if [ -n "$PACK" ]; then
  [ -f "$PACK/textures.ini" ] || { echo "sprite_pack: no textures.ini in $PACK"; exit 2; }
  PACK=$(cd "$PACK" && pwd)
fi
mkdir -p "$DIR"
DIR=$(cd "$DIR" && pwd)
START=$SECONDS
SUMMARY="$DIR/summary.txt"
: > "$SUMMARY"
say() { echo "$*"; echo "$*" >> "$SUMMARY"; }
# A path as Python and the game take it: Git Bash's /c/... as C:/... on Windows.
native() { if [ -n "$WINDOWS" ]; then cygpath -m "$1"; else echo "$1"; fi; }

# guarded LOG CMD...: runs CMD with its output to LOG once no other PureNative runs (tools/lib.sh's wait_game, up to
# --wait seconds; exit 2 after that); returns CMD's status. The suite's runs pass --wait to tools/frame_regress.sh
# instead, which waits the same way.
guarded() {
  local log=$1
  shift
  wait_game sprite_pack "$WAIT" || { say "sprite_pack: another game kept running for $WAIT s; try again later"; exit 2; }
  "$@" > "$log" 2>&1
}

# The keys of a pack folder's textures.ini (its `<key> = <file>` lines), 0 without one.
keys() {
  if [ -f "$1/textures.ini" ]; then grep -c '^[0-9a-fA-F]\{24\} *=' "$1/textures.ini"; else echo 0; fi
}

# ---------------------------------------------------------------------------------------------------- the build
if [ -z "$PACK" ]; then
  DUMP="$DIR/dump"
  rm -rf "$DUMP" "$DIR/pack" "$DIR/regress" "$DIR/sweep"
  mkdir -p "$DUMP"
  say "sprite pack $(date '+%Y-%m-%d %H:%M'), commit $(git rev-parse --short HEAD 2>/dev/null || echo unknown):" \
    "headless on Metal with PURE_SPRITE_UPSCALE=1, PURE_SPRITE_DUMP=$DUMP"
  echo "the frame regression suite's routes (tools/frame_regress.sh --out $DIR/regress) ..."
  tools/frame_regress.sh --wait "$WAIT" --out "$DIR/regress" --shell headless --backend metal \
    --env PURE_SPRITE_UPSCALE=1 --env "PURE_SPRITE_DUMP=$DUMP" > "$DIR/regress.stdout" 2>&1
  rc=$?
  if [ $rc -eq 2 ]; then
    cat "$DIR/regress.stdout"
    say "sprite_pack: tools/frame_regress.sh could not run"
    exit 2
  fi
  grep '^run .*: run_boot exit' "$DIR/regress.stdout" | sed 's/, log .*//; s/^/  /'
  n=$(keys "$DUMP/pack")
  say "  the suite's 18 scenes' routes: $n keys"
  for cell in $RACE_CELLS; do
    mode=${cell%%:*}; track=${cell#*:}
    echo "$mode $track to its results screen (tools/campaign_sweep.py $mode $track --no-damage, the race paced) ..."
    guarded "$DIR/sweep.$mode-$track.stdout" env PURE_SPRITE_UPSCALE=1 "PURE_SPRITE_DUMP=$DUMP" \
      python3 tools/campaign_sweep.py "$mode" "$track" --no-damage --out "$DIR/sweep"
    outcome=$(grep "^\[sweep\] $mode-$track: [A-Z]" "$DIR/sweep.$mode-$track.stdout" | tail -1 |
      sed 's/^\[sweep\] [^:]*: //; s/, [0-9]* laps.*//')
    before=$n
    n=$(keys "$DUMP/pack")
    say "  $mode $track to its results screen (${outcome:-no outcome line}): +$((n - before)) keys"
  done
  if [ ! -f "$DUMP/pack/textures.ini" ]; then
    say "sprite_pack: no pack was written (no texture upscaled?); the runs are in $DIR"
    exit 2
  fi
  mv "$DUMP/pack" "$DIR/pack"
  say "pack: $DIR/pack, $(keys "$DIR/pack") keys, $(du -sh "$DIR/pack" | awk '{ print $1 }') (the game's art: keep it under" \
    "out/, never commit it)"
  say "install it as textures/$GAME_ID in the data directory (or through the Esc menu's texture pack screen) for the" \
    "Vulkan renderer"
  PACK="$DIR/pack"
  if [ $CHECK = no ]; then
    say "sprite_pack: built ($(( (SECONDS - START) / 60 ))m $(( (SECONDS - START) % 60 ))s)"
    exit 0
  fi
  say ""
fi

# ---------------------------------------------------------------------------------------------------- the check
CHECKDIR="$DIR/check"
DATA="$CHECKDIR/data"
rm -rf "$CHECKDIR"
mkdir -p "$CHECKDIR"
say "sprite pack check $(date '+%Y-%m-%d %H:%M'): $PACK in the Vulkan window, $CHECK_SCENES without and with it"
# A fresh scratch data directory (port.SCRATCH_SETTINGS: the enhancements off, the menu hint seen) with the pack
# installed where the loader looks without a folder setting: textures/<disc id>.
python3 - "$(native "$PACK")" "$(native "$DATA")" "$GAME_ID" <<'EOF' || exit 2
import os, shutil, sys
sys.path.insert(0, "tools")
from purelib import port  # noqa: E402  (tools/purelib/port.py)
pack, data, game = sys.argv[1:4]
port.scratch_data_dir({}, data)
shutil.copytree(pack, os.path.join(data, "textures", game))
EOF
for state in off on; do
  if [ $state = off ]; then
    envs=(--env PURE_TEXTURE_PACK=0)
  else
    envs=(--env PURE_TEXTURE_PACK=1 --env PURE_TRACE_TEXTURE_PACK=1)
  fi
  echo "the Vulkan window, pack $state (tools/frame_regress.sh --out $CHECKDIR/$state) ..."
  tools/frame_regress.sh --wait "$WAIT" --out "$CHECKDIR/$state" --shell vulkan --backend vulkan \
    --only "$(echo $CHECK_SCENES | tr ' ' ',')" --env "PURE_DATA_DIR=$(native "$DATA")" "${envs[@]}" \
    > "$CHECKDIR/$state.stdout" 2>&1
  if [ $? -eq 2 ]; then
    cat "$CHECKDIR/$state.stdout"
    say "sprite_pack: tools/frame_regress.sh could not run"
    exit 2
  fi
  grep '^run .*: run_boot exit' "$CHECKDIR/$state.stdout" | sed 's/, log .*//; s/^/  /'
done

python3 - "$(native "$PACK")" "$(native "$CHECKDIR")" "$CHECK_SCENES" "$HUD_SCENES" "$GAME_ID" \
  "$((SECONDS - START))" "$(native "$SUMMARY")" <<'EOF'
import os, re, subprocess, sys
sys.path.insert(0, "tools")
import imgdiff  # noqa: E402  (tools/imgdiff.py)

pack, check, scenes, hud_scenes, game, seconds, summary = sys.argv[1], sys.argv[2], sys.argv[3].split(), \
    sys.argv[4].split(), sys.argv[5], int(sys.argv[6]), sys.argv[7]
MIN_KEYS, MIN_DRAWN = 40, 10
DIFF_TOL, MIN_DIFF = 24, 0.01           # with the pack against without: at least 1% of pixels over tol 24
log_lines = []


def note(text=""):
    print(text)
    log_lines.append(text)


def scene_table():
    """{scene: (route, frame, reference, tol, limit)} from tools/frame_regress.sh's SCENES table."""
    with open("tools/frame_regress.sh") as f:
        text = f.read()
    block = text.split("SCENES='", 1)[1].split("'", 1)[0]
    table = {}
    for line in block.splitlines():
        fields = line.split("#", 1)[0].split()
        if len(fields) >= 8:
            table[fields[0]] = (fields[1], int(fields[2]), fields[3], int(fields[4]), float(fields[5]))
    return table


def read_pack(folder):
    """(the hash option, the keys of [hashes], the files they name, those missing, whether every entry is
    `<key> = <key>.png`: the game's own art as the build writes it), as the loader reads textures.ini."""
    section, hash_kind, keys, named, missing, own_art = "", None, set(), {}, {}, True
    with open(os.path.join(folder, "textures.ini"), errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line[0] in "#;":
                continue
            if line.startswith("["):
                section = line[1:].split("]", 1)[0].strip().lower()
                continue
            if "=" not in line:
                continue
            name, value = (part.strip() for part in line.split("=", 1))
            if section == "options" and name.lower() == "hash":
                hash_kind = value.lower()
            elif section == "hashes":
                keys.add(name.lower())
                own_art = own_art and value.lower() == name.lower() + ".png"
                if value and value not in named:
                    named[value] = True
                    if not os.path.isfile(os.path.join(folder, value)):
                        missing[value] = True
    return hash_kind, keys, list(named), list(missing), own_art and bool(keys)


def reduce(path, reduced):
    """The capture at `path` reduced to 480x272 by the centre pixel of each S x S block (tools/imgdiff.py's
    reduce_centres, as tools/scale_check.sh and tools/sprite_check.sh reduce), written to `reduced`; (S, None) or
    (None, why)."""
    try:
        return imgdiff.reduce_centres(path, reduced), None
    except imgdiff.NotScaled as e:
        return None, str(e)


def hud(scene, capture, frame):
    """tools/hud_check.py on the capture, written as check/hud/<scene>/h<frame>.bmp: (passed, its last line)."""
    where = os.path.join(check, "hud", scene)
    os.makedirs(where, exist_ok=True)
    w, h, rgb = imgdiff.load_rgb(capture)
    imgdiff._write_bmp(os.path.join(where, f"h{frame}.bmp"), w, h, rgb, 3, 24)
    r = subprocess.run([sys.executable, "tools/hud_check.py", where, "--expect", "1"], capture_output=True, text=True)
    last = (r.stdout.strip().splitlines() or ["(no output)"])[-1]
    return r.returncode == 0, last


failures = []
hash_kind, keys, named, missing, own_art = read_pack(pack)
all_missing = bool(named) and len(missing) == len(named)
pack_ok = len(keys) >= MIN_KEYS and hash_kind in ("xxh64", "xxh32") and not all_missing
note(f"the pack: {len(keys)} keys (at least {MIN_KEYS}), hash {hash_kind}, {len(named)} files named, "
     f"{len(missing)} of them missing{' (' + ', '.join(missing[:3]) + ')' if missing else ''}"
     f"{' (every one: FAIL)' if all_missing else ''}, "
     f"{'the game' + chr(39) + 's own art' if own_art else 'new art'}: {'PASS' if pack_ok else 'FAIL'}")
if not pack_ok:
    failures.append("the pack")

# What the runs with the pack logged: the pack opened (`[texpack] N textures from FOLDER`), the keys the lookups found
# (`[texpack] 0x... key KEY -> NAME`), the images decoded and uploaded for the draws that sample them, the draws
# replaced and the budget line's images on the GPU, per route.
table = scene_table()
routes = {table[s][0] for s in scenes}
opened, uploaded, replaced, decoded, refused, absent, per_route = [], set(), 0, set(), [], set(), []
for route in sorted(routes):
    log = os.path.join(check, "on", route.replace(".txt", "") + ".log")
    if not os.path.isfile(log):
        opened.append((route, None))
        continue
    found = None
    r = {"keys": set(), "decoded": set(), "uploaded": set(), "replaced": 0, "peak": (0, 0), "absent": set()}
    with open(log, errors="replace") as f:
        for line in f:
            m = re.match(r"\[texpack\] (\d+) textures from (.*)$", line)
            if m:
                found = (int(m[1]), m[2].strip())
            m = re.match(r"\[texpack\] 0x\S+ \S+ fmt=\d+ key (\S+) -> ", line)
            if m:
                r["keys"].add(m[1])
            m = re.match(r"\[texpack\] frame \d+: uploaded (\S+)", line)
            if m:
                r["uploaded"].add(m[1])
            m = re.match(r"\[texpack\] decoded (\S+)", line)
            if m:
                r["decoded"].add(m[1])
            m = re.match(r"\[texpack\] frame \d+: (\d+) draws replaced in \d+ frames, (\d+) images on the GPU "
                         r"\((\d+) MB\)", line)
            if m:
                r["replaced"] += int(m[1])
                r["peak"] = max(r["peak"], (int(m[3]), int(m[2])))
            # By its end: two loader threads' lines can run together on stderr.
            m = re.search(r"(\S+): missing or unreadable$", line.strip())
            if m:
                r["absent"].add(m[1])
            elif line.startswith("[texpack] cannot use") or line.startswith("[texpack] no texture pack") or \
                    "Not loaded" in line:
                refused.append(line.strip())
    uploaded |= r["uploaded"]
    decoded |= r["decoded"]
    replaced += r["replaced"]
    absent |= r["absent"]
    per_route.append((route, r))
    opened.append((route, found))
for route, found in opened:
    ok = found is not None and found[0] == len(keys) and found[1].replace("\\", "/").endswith("textures/" + game)
    note(f"opened by the Vulkan renderer, route {route}: "
         + (f"{found[0]} textures from {found[1]}" if found else "no `[texpack] N textures from` line")
         + f": {'PASS' if ok else 'FAIL'}")
    if not ok:
        failures.append(f"not opened on {route}")
for route, r in per_route:
    note(f"  route {route}: {len(r['keys'])} keys found in the pack, {len(r['decoded'])} images decoded, "
         f"{len(r['uploaded'])} uploaded, {r['replaced']} draws replaced, peak {r['peak'][1]} images on the GPU "
         f"({r['peak'][0]} MB), {len(r['absent'])} named files missing or unreadable")
drawn_ok = len(uploaded) >= MIN_DRAWN and bool(per_route) and all(r["replaced"] > 0 for _, r in per_route)
note(f"drawn: {len(uploaded)} distinct images of the pack uploaded for draws (at least {MIN_DRAWN}), {len(decoded)} "
     f"decoded, {replaced} draws replaced in the traced 60-frame windows (some on each route): "
     f"{'PASS' if drawn_ok else 'FAIL'}")
if not drawn_ok:
    failures.append("too few replacements drawn")
note(f"refused: {len(refused)} lines for images the pack holds; {len(absent)} files the ini names missing or "
     f"unreadable (counted, not a rule{': ' + ', '.join(sorted(absent)[:3]) if absent else ''}): "
     f"{'PASS' if not refused else 'FAIL'}")
for line in refused[:5]:
    note(f"  {line}")
if refused:
    failures.append("images refused")

note("")
note(f"each scene in the Vulkan window: the capture with the pack against the one without at tol {DIFF_TOL} (at least "
     f"{MIN_DIFF:.0%}), both reduced to 480x272 by their blocks' centre pixels against the scene's reference at the "
     f"scene's tol and limit (tools/frame_regress.sh), and the race HUD (tools/hud_check.py):")
note(f"{'scene':<10} {'size':>9} {'on vs off':>9} {'off red.':>9} {'on red.':>8} {'limit':>6} {'tol':>4} {'HUD':>4}  result")
passed = 0
for scene in scenes:
    route, frame, ref, tol, limit = table[scene]
    on, off = (os.path.join(check, s, "shots", scene + ".png") for s in ("on", "off"))
    if not (os.path.isfile(on) and os.path.isfile(off)):
        note(f"{scene:<10} {'-':>9} {'-':>9} {'-':>9} {'-':>8} {limit:>6} {tol:>4} {'-':>4}  FAIL (no capture "
             f"{'with' if not os.path.isfile(on) else 'without'} the pack)")
        failures.append(scene)
        continue
    w, h, _ = imgdiff.load_rgb(on)
    why = []
    vs = imgdiff.compare_files(on, off, DIFF_TOL, 1.0)
    if vs["fraction"] < MIN_DIFF:
        why.append(f"differs from the capture without the pack in under {MIN_DIFF:.0%}")
    texts = {}
    for state, path in (("off", off), ("on", on)):
        reduced = os.path.join(check, state, scene + ".reduced.png")
        s, bad = reduce(path, reduced)
        if bad:
            texts[state] = "-"
            if state == "on":
                why.append(bad)
            continue
        diff = os.path.join(check, f"{scene}.{state}.diff.png")
        r = imgdiff.compare_files(reduced, ref, tol, limit, diff)
        texts[state] = f"{r['fraction']:.4f}"
        if r["result"] == "PASS":
            os.remove(diff)
        elif state == "on" and own_art:
            why.append(f"reduced over the limit, diff {diff}")
    hud_text = "-"
    if scene in hud_scenes:
        ok, last = hud(scene, on, frame)
        hud_text = "yes" if ok else "no"
        if not ok:
            why.append(f"no HUD ({last})")
    passed += not why
    if why:
        failures.append(scene)
    note(f"{scene:<10} {f'{w}x{h}':>9} {vs['fraction']:>9.4f} {texts['off']:>9} {texts['on']:>8} {limit:>6} {tol:>4} "
         f"{hud_text:>4}  " + ("PASS" if not why else "FAIL (" + "; ".join(why) + ")"))

verdict = "PASS" if not failures else "FAIL"
note("")
note(f"sprite pack check: {passed}/{len(scenes)} scenes pass, {len(keys)} keys, {len(uploaded)} drawn "
     f"({seconds // 60}m {seconds % 60}s)")
note(f"sprite_pack: {verdict}")
with open(summary, "a") as f:
    f.write("\n".join(log_lines) + "\n")
sys.exit(0 if verdict == "PASS" else 1)
EOF
