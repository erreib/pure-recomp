#!/bin/bash
# tools/bundle.sh [--zip] [--dist]   pack "Wipeout Pure.app" with the framework's packer (task 029, docs/release.md)
# tools/bundle.sh --check DIR        check the packed app (below); exit 0 when every check passes
#
# Packing: tools/build.sh release when build/release/bin/PureNative is missing or older than the sources (the first
# time 10 to 20 minutes, the corpus compiles again in Release), then
#   vendor/portablekit/scripts/release_macos.sh --game . --no-dmg build/release
# which fetches the pinned SDL3, Vulkan loader, MoltenVK, CJK font and FFmpeg source (each checked by SHA-256), builds
# SDL3 and the loader for macOS 13 once (out/release-macos/deps), assembles the app in out/release-macos/stage, links
# every library inside it, marks the binaries for macOS 13 once their system imports are found in the macOS 13 SDK,
# signs everything ad hoc and checks the app for game data and paths of this machine. Before the packer runs,
# config/metal_pipelines.txt is copied into build/release/bin/app_resources, whose contents packaging/release.env's
# RELEASE_RESOURCES ships in Contents/Resources (task 042: the Metal backend's pre-warm list, which it looks for there
# first), so the app is signed with the list inside.
#   --zip   also the zip archive, in out/release-macos/dist with the FFmpeg source archive and SHA256SUMS
#   --dist   the disk image and the zip archive, in out/release-macos/dist
# The version is CMakeLists.txt's project version and the commit, 0.1.0-<hash>[-dirty].
#
# --check DIR (task 029's Verify line; DIR/data and the shots are made afresh, nothing outside DIR is written):
#   bundle   codesign --verify --deep --strict, signed ad hoc; every Mach-O loads only system libraries and libraries
#            inside the bundle (no /opt/homebrew), every @rpath library is in Contents/Frameworks, and rpaths are
#            relative to the executable or the library
#   machine  no path of this machine (the home directory, /<user name>/) in any file
#   names    no file named like game data (the packer's names and packaging/release.env's RELEASE_GAME_NAMES)
#   content  no file holds a disc image (CD001 at 32769), a PSP executable (MIPS ELF, ~PSP), a PBP or a PARAM.SFO; the
#            strings UCUS98612, .iso, .wad, EBOOT, BOOT.BIN and the disc image's SHA-256 prefix are in no file but the
#            executable, and there only inside its own text (the disc id it checks an image against, the names of
#            the files it writes, its messages: listed with --check), never the SHA-256
#   setup    the bundled executable with PURE_DATA_DIR=DIR/data and --install "$(readlink disc.iso)" (no other PURE_
#            variable): exit 0, DIR/data holds EBOOT.ELF, settings.ini and the copied disc.iso (as big as the image)
#   route    the bundled executable again with only PURE_DATA_DIR and the route's variables (PURE_INPUT_SCRIPT from
#            config/pad_scripts/frontend.txt, PURE_SCREENSHOT_DIR=DIR/shots with PURE_SCREENSHOT_EVERY=0,
#            PURE_EXIT_AT_FRAME=2200): it plays the
#            installed game (Executable and Disc image in DIR/data) in the default shell and backend, Metal, reaches
#            frame 2200, and DIR/shots/title.png is within tol 24, max-frac 0.05 of ref/title.png (the suite's limit)
#   finder   open "<app>" (LaunchServices, as a double click in Finder; --env passes the same data directory and
#            route, --stdout DIR/finder.log): the Metal window opens and the route's title shot,
#            DIR/finder_shots/title.png (the window's picture at its pixel size), is within the same limit
#   prewarm  (task 042) Contents/Resources/metal_pipelines.txt is config/metal_pipelines.txt, and the route and finder
#            runs each print `[metal] pre-warm: R render pipelines ... and D depth-stencil states from` that copy,
#            with its own counts; their exit lines' "not in the list" counts are reported
# route and finder need the installation: when setup fails they are reported FAIL without running (with no game the
# app would show its setup screens and wait). They run silent (task 042): after the setup, DIR/data/settings.ini gets
# audio.mute=1, the in-game menu's Mute, so the app opens the audio device at gain 0; the app uses no data directory
# but DIR/data. Prints PASS or FAIL per check and the bundle's files with their sizes (also in
# DIR/bundle_files.txt).
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh
ROOT=$PWD
# The Game Porting Toolkit's x86_64 clang 8 must not be the `clang` anything here finds.
PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'game-porting-toolkit' | paste -sd: -)
export PATH

NAME="Wipeout Pure"
STAGE=out/release-macos/stage
APP="$ROOT/$STAGE/$NAME.app"
EXE="$APP/Contents/MacOS/$NAME"
BUILD=build/release
RESOURCES=app_resources   # the folder of $BUILD/bin whose contents RELEASE_RESOURCES ships in Contents/Resources
LIST=metal_pipelines.txt  # the Metal backend's pre-warm list, config/metal_pipelines.txt, in Contents/Resources
TITLE_TOL=24
TITLE_MAX_FRAC=0.05
ROUTE_FRAMES=2200

usage() { sed -n '2,3p' "$0"; exit 2; }

disc_image() {   # Erik's disc image: where disc.iso points
  local target
  [ -L disc.iso ] || { echo "disc.iso is not a link (tools/worktree_init.sh, docs/setup.md)" >&2; return 1; }
  target=$(readlink disc.iso)
  case "$target" in /*) ;; *) target="$ROOT/$target" ;; esac
  [ -f "$target" ] || { echo "disc.iso dangles: $target. Stop here; do not look for the image elsewhere." >&2; return 1; }
  printf '%s\n' "$target"
}

list_counts() {   # list_counts FILE: "R render pipelines, D depth-stencil states", as the pre-warm reads a list
  printf '%s render pipelines, %s depth-stencil states' "$(grep -c '^render ' "$1")" "$(grep -c '^depth ' "$1")"
}

# ---------------------------------------------------------------------------------------------------------------------
pack() {
  local packer_args=(--no-dmg) newer version
  case "${1:-}" in
    --zip) packer_args+=(--zip) ;;
    --dist) packer_args=(--zip) ;;
    "") ;;
    *) usage ;;
  esac
  if [ ! -x $BUILD/bin/PureNative ]; then
    echo "== $BUILD/bin/PureNative is missing: tools/build.sh release (10 to 20 minutes the first time)"
    tools/build.sh release || exit 1
  else
    # config/metal_pipelines.txt is not compiled in: the packer ships it (below), so a newer list needs no build.
    newer=$(find src config patches CMakeLists.txt CMakePresets.json generated/ vendor/portablekit/host \
              vendor/portablekit/src vendor/portablekit/include vendor/portablekit/cmake \
              vendor/portablekit/CMakeLists.txt third_party -type f ! -path config/metal_pipelines.txt \
              -newer $BUILD/bin/PureNative 2>/dev/null | head -1)
    if [ -n "$newer" ]; then
      echo "== $BUILD/bin/PureNative is older than $newer: tools/build.sh release"
      tools/build.sh release || exit 1
    else
      echo "== $BUILD/bin/PureNative is up to date"
    fi
  fi
  # The Metal backend's pre-warm list (task 042): packaging/release.env's RELEASE_RESOURCES ships the contents of
  # $BUILD/bin/$RESOURCES in Contents/Resources, where the backend looks for metal_pipelines.txt first; the packer
  # signs the app after copying them, so the list is sealed with it.
  rm -rf "$BUILD/bin/$RESOURCES"
  mkdir -p "$BUILD/bin/$RESOURCES"
  cp "config/$LIST" "$BUILD/bin/$RESOURCES/" || exit 1
  echo "== $BUILD/bin/$RESOURCES/$LIST for Contents/Resources: $(list_counts "config/$LIST")"
  version="$(sed -n 's/^project(PureRecomp VERSION \([0-9.]*\).*/\1/p' CMakeLists.txt)-$(git describe --always --dirty)"
  echo "== packing $NAME $version: release_macos.sh --game . ${packer_args[*]} $BUILD"
  # The packer is not executable at the pin (mode 100644), so bash runs it.
  bash vendor/portablekit/scripts/release_macos.sh --game . --version "$version" "${packer_args[@]}" $BUILD || {
    echo "bundle: the packer failed (above)"; exit 1; }
  echo
  echo "app: $STAGE/$NAME.app"
  [ -d out/release-macos/dist ] && ls out/release-macos/dist | sed 's#^#dist: out/release-macos/dist/#'
  exit 0
}

# ---------------------------------------------------------------------------------------------------------------------
FAILED=0
result() {   # result NAME PASS|FAIL DETAIL
  printf '%-8s %s  %s\n' "$1" "$2" "$3"
  [ "$2" = PASS ] || FAILED=$((FAILED + 1))
}

macho_files() {
  find "$APP" -type f -print0 | while IFS= read -r -d '' f; do
    [ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" = cffaedfe ] && printf '%s\n' "$f"
  done
}

# Runs a command with stdout and stderr in LOG, killed after SECONDS; exit status of the command, 124 on the deadline.
run_bounded() {
  local seconds=$1 log=$2 pid ticks=0
  shift 2
  "$@" > "$log" 2>&1 < /dev/null &
  pid=$!
  while kill -0 $pid 2> /dev/null; do
    if [ $ticks -ge $((seconds * 10)) ]; then
      kill $pid 2> /dev/null; sleep 2; kill -9 $pid 2> /dev/null
      wait $pid 2> /dev/null
      echo "[bundle] deadline: killed after $seconds s" >> "$log"
      return 124
    fi
    sleep 0.1
    ticks=$((ticks + 1))
  done
  wait $pid
}

# The environment the app runs with, `env "${CLEAN_ENV[@]}" VAR=VALUE ... program`: no PURE_ variable of this shell
# (PURE_GAME_DIR, PURE_SHELL, PURE_GE_BACKEND, PURE_NO_RENDER ... would each change what is checked).
CLEAN_ENV=()
for var in $(env | sed -n 's/^\(PURE_[A-Za-z0-9_]*\)=.*/\1/p'); do CLEAN_ENV+=(-u "$var"); done

route_script() {   # the route's steps joined with ';' as tools/run_boot.py does
  grep -Ev '^[[:space:]]*(#|$)' config/pad_scripts/frontend.txt | paste -sd';' -
}

bmp_to_png() {
  python3 - "$1" <<'PY'
import os, sys
sys.path.insert(0, "tools")
import png
d = sys.argv[1]
for name in sorted(os.listdir(d)):
    if name.lower().endswith(".bmp"):
        w, h, c, data = png.read_bmp(os.path.join(d, name))
        png.write_png(os.path.join(d, os.path.splitext(name)[0] + ".png"), w, h, c, data)
PY
}

title_diff() {   # title_diff PNG: imgdiff's line, exit status 0 within the limit
  python3 tools/imgdiff.py "$1" ref/title.png --tol $TITLE_TOL --max-frac $TITLE_MAX_FRAC 2>&1
}

# route: the installed game, the default shell and backend, the frontend route.
route_check() {   # route_check DIR DATA SCRIPT
  local dir=$1 data=$2 script=$3 rc line shell_line exe_line disc_line
  run_bounded 180 "$dir/route.log" env ${CLEAN_ENV[@]+"${CLEAN_ENV[@]}"} PURE_DATA_DIR="$data" \
    PURE_INPUT_SCRIPT="$script" PURE_SCREENSHOT_DIR="$dir/shots" PURE_SCREENSHOT_EVERY=0 \
    PURE_EXIT_AT_FRAME=$ROUTE_FRAMES "$EXE"
  rc=$?
  bmp_to_png "$dir/shots"
  shell_line=$(grep -m1 '^\[shell\] metal' "$dir/route.log" || true)
  exe_line=$(grep -m1 '^Executable: ' "$dir/route.log" || true)
  disc_line=$(grep -m1 '^Disc image: ' "$dir/route.log" || true)
  if ! grep -q "^\[pure\] exit at frame $ROUTE_FRAMES" "$dir/route.log"; then
    result route FAIL "exit $rc, frame $ROUTE_FRAMES not reached (log $dir/route.log)"
  elif [ "$exe_line" != "Executable: $data/EBOOT.ELF" ] || [ "$disc_line" != "Disc image: $data/disc.iso" ]; then
    result route FAIL "not the installed game: '$exe_line', '$disc_line'"
  elif [ -z "$shell_line" ]; then
    result route FAIL "not the Metal shell (log $dir/route.log)"
  elif [ ! -f "$dir/shots/title.png" ]; then
    result route FAIL "no title shot in $dir/shots"
  else
    line=$(title_diff "$dir/shots/title.png")
    if [ $? -eq 0 ]; then result route PASS "frame $ROUTE_FRAMES from $data, $shell_line; title: $line"
    else result route FAIL "title: $line"; fi
  fi
}

# finder: the same through LaunchServices, as a double click in Finder starts it.
finder_check() {   # finder_check DIR DATA SCRIPT
  local dir=$1 data=$2 script=$3 line shell_line finder_pid ticks=0
  # open appends to --stdout and --stderr: without this a check run into the same DIR would read an earlier run's log.
  rm -f "$dir/finder.log" "$dir/finder.stderr.log"
  open -n -W --env PURE_DATA_DIR="$data" --env "PURE_INPUT_SCRIPT=$script" \
    --env PURE_SCREENSHOT_DIR="$dir/finder_shots" --env PURE_SCREENSHOT_EVERY=0 --env PURE_EXIT_AT_FRAME=$ROUTE_FRAMES \
    --stdout "$dir/finder.log" --stderr "$dir/finder.stderr.log" "$APP" &
  finder_pid=$!
  while kill -0 $finder_pid 2> /dev/null && [ $ticks -lt 1800 ]; do sleep 0.1; ticks=$((ticks + 1)); done
  if kill -0 $finder_pid 2> /dev/null; then
    pkill -f "$EXE" 2> /dev/null
    wait $finder_pid 2> /dev/null
    result finder FAIL "still running after 180 s (log $dir/finder.log)"
    return
  fi
  bmp_to_png "$dir/finder_shots"
  shell_line=$(grep -m1 '^\[shell\] metal' "$dir/finder.log" || true)
  if ! grep -q "^\[pure\] exit at frame $ROUTE_FRAMES" "$dir/finder.log"; then
    result finder FAIL "frame $ROUTE_FRAMES not reached (log $dir/finder.log)"
  elif [ -z "$shell_line" ] || [ ! -f "$dir/finder_shots/title.png" ]; then
    result finder FAIL "no Metal window or no title shot (log $dir/finder.log)"
  else
    line=$(title_diff "$dir/finder_shots/title.png")
    if [ $? -eq 0 ]; then result finder PASS "open \"$NAME.app\": $shell_line; window picture $dir/finder_shots/title.png: $line"
    else result finder FAIL "title: $line"; fi
  fi
}

# prewarm: the app carries the checkout's pre-warm list in Contents/Resources, and both runs of the packed app (route
# and finder) pre-warmed from that copy (task 042). The backend looks there first (metal_pipelines.mm (find_pipeline_list),
# find_pipeline_list) and prints `[metal] pre-warm: R render pipelines (made asynchronously) and D depth-stencil
# states from PATH, T ms at start`; R and D must be the copy's own counts. The exit line's "not in the list" count is
# reported, not checked: it measures the list's coverage of the route, not the bundle.
prewarm_check() {   # prewarm_check DIR
  local dir=$1 packed="$APP/Contents/Resources/$LIST" log run line fields renders depths path ended bad="" detail=""
  local want_renders want_depths
  if [ ! -f "$packed" ]; then
    result prewarm FAIL "no $LIST in Contents/Resources (tools/bundle.sh stages it for the packer)"
    return
  fi
  want_renders=$(grep -c '^render ' "$packed")
  want_depths=$(grep -c '^depth ' "$packed")
  cmp -s "$packed" "config/$LIST" || bad+="Contents/Resources/$LIST is not config/$LIST (pack again); "
  for run in route finder; do
    log="$dir/$run.log"
    line=$(grep -m1 '^\[metal\] pre-warm: ' "$log" 2> /dev/null || true)
    fields=$(printf '%s\n' "$line" | sed -n 's/^\[metal\] pre-warm: \([0-9]*\) render pipelines (made asynchronously) and \([0-9]*\) depth-stencil states from \(.*\), [^,]* ms at start.*$/\1 \2 \3/p')
    renders="" depths="" path=""
    [ -n "$fields" ] && read -r renders depths path <<< "$fields"
    if [ -z "$line" ]; then
      bad+="$run: no [metal] pre-warm line (log $log); "
    elif [ -z "$fields" ] || [ ! "$path" -ef "$packed" ]; then
      bad+="$run: not the Resources copy: '$line'; "
    elif [ "$renders" != "$want_renders" ] || [ "$depths" != "$want_depths" ] || [[ "$line" == *"lines not read"* ]]; then
      bad+="$run: read $renders render pipelines and $depths depth-stencil states of $want_renders and $want_depths: '$line'; "
    fi
    ended=$(grep '^\[metal\] pipelines: ' "$log" 2> /dev/null | tail -1 | sed -n 's/.*made by a draw (\(.*\)), [0-9]* taken from the pre-warm.*/\1/p')
    detail+="; $run: ${ended:-no exit line}"
  done
  if [ -n "$bad" ]; then result prewarm FAIL "$bad"
  else result prewarm PASS "route and finder pre-warmed from Contents/Resources/$LIST (config/$LIST, $want_renders render pipelines, $want_depths depth-stencil states)$detail"; fi
}

check() {
  local dir=$1 iso iso_sha detail
  [ -x "$EXE" ] || { echo "no $EXE: tools/bundle.sh first"; exit 2; }
  [ -f ref/title.png ] || { echo "ref/title.png missing (copy the PPSSPP captures from the main checkout's ref/)"; exit 2; }
  iso=$(disc_image) || exit 2
  mkdir -p "$dir"
  dir=$(cd "$dir" && pwd)
  echo "bundle check $(date '+%Y-%m-%d %H:%M'): $STAGE/$NAME.app, data $dir/data"

  # bundle: signature and libraries.
  local machos bad_links=""
  machos=$(macho_files)
  detail="$(printf '%s\n' "$machos" | wc -l | tr -d ' ') Mach-O files"
  if ! codesign --verify --deep --strict "$APP" 2> "$dir/codesign.txt"; then
    result bundle FAIL "codesign --verify: $(head -1 "$dir/codesign.txt")"
  elif ! codesign -dv "$APP" 2>&1 | grep -q '^Signature=adhoc'; then
    result bundle FAIL "not signed ad hoc: $(codesign -dv "$APP" 2>&1 | grep '^Signature' || echo no signature)"
  else
    while IFS= read -r f; do
      while read -r lib; do
        case "$lib" in
          /usr/lib/*|/System/Library/*) ;;
          @rpath/*) [ -f "$APP/Contents/Frameworks/${lib#@rpath/}" ] || bad_links+="$(basename "$f"): $lib (not in Frameworks); " ;;
          @executable_path/*|@loader_path/*) ;;
          *) bad_links+="$(basename "$f"): $lib; " ;;
        esac
      done < <(otool -L "$f" | tail -n +2 | awk '{ print $1 }')
      while read -r rpath; do
        case "$rpath" in @executable_path*|@loader_path*) ;; *) bad_links+="$(basename "$f") rpath: $rpath; " ;; esac
      done < <(otool -l "$f" | awk '$1 == "cmd" && $2 == "LC_RPATH" { getline; getline; print $2 }')
    done <<< "$machos"
    if [ -n "$bad_links" ]; then
      result bundle FAIL "libraries outside the bundle: $bad_links"
    else
      result bundle PASS "signed ad hoc, $detail, every library is the system's or in Contents/Frameworks"
    fi
  fi

  # machine: no path of this machine.
  local leaks
  leaks=$(LC_ALL=C grep -rlaF -e "$HOME" -e "/$(id -un)/" "$APP" || true)
  if [ -n "$leaks" ]; then result machine FAIL "$(printf '%s' "$leaks" | tr '\n' ' ')"
  else result machine PASS "no $HOME, no /$(id -un)/ in any file"; fi

  # names: no file named like game data.
  local names patterns base pattern bad_names=""
  # shellcheck disable=SC1091
  patterns=$(. packaging/release.env; printf '%s' "$RELEASE_GAME_NAMES")
  while IFS= read -r -d '' f; do
    base=$(basename "$f" | tr '[:upper:]' '[:lower:]')
    case "$base" in
      eboot*|*.iso|*.cso|*.pbp|*.prx|*.elf|*.ovl|*.bin|param.sfo|umd_data*|ms0|savedata)
        bad_names+="$f; "; continue ;;
    esac
    set -f
    for pattern in $patterns; do
      # shellcheck disable=SC2254
      case "$base" in $pattern) bad_names+="$f; " ;; esac
    done
    set +f
  done < <(find "$APP" -print0)
  if [ -n "$bad_names" ]; then result names FAIL "$bad_names"
  else result names PASS "no file named like game data ($(find "$APP" | wc -l | tr -d ' ') entries)"; fi

  # content: no game file by its header, the game's strings only in the executable's own text.
  local head bad_content="" strings_file="$dir/exe_strings.txt" hits hit pattern_list p found listed
  while IFS= read -r -d '' f; do
    head=$(head -c 20 "$f" | od -An -tx1 | tr -d ' \n')
    case "$head" in
      7f454c46*) [ "${head:36:4}" = 0800 ] && bad_content+="$f (PSP executable); " ;;
      00504250*) bad_content+="$f (PBP); " ;;
      7e505350*) bad_content+="$f (encrypted PSP module); " ;;
      00505346*) bad_content+="$f (PARAM.SFO); " ;;
    esac
    if [ "$(stat -f %z "$f")" -gt 32774 ] &&
       [ "$(dd if="$f" bs=1 skip=32769 count=5 2> /dev/null | LC_ALL=C tr -d '\0')" = CD001 ]; then
      bad_content+="$f (disc image); "
    fi
  done < <(find "$APP" -type f -print0)
  iso_sha=$(shasum -a 256 "$iso" | cut -c1-16)
  strings -a -n 4 "$EXE" > "$strings_file"
  listed=""
  for p in UCUS98612 .iso .wad EBOOT BOOT.BIN "$iso_sha"; do
    hits=$(LC_ALL=C grep -rlaF -- "$p" "$APP" || true)
    [ -n "$hits" ] || continue
    while IFS= read -r hit; do
      if [ "$hit" = "$EXE" ] && [ "$p" != "$iso_sha" ]; then
        found=$(LC_ALL=C grep -aF -- "$p" "$strings_file" | LC_ALL=C sort -u)
        if [ -z "$found" ]; then
          bad_content+="executable: $p outside its text strings; "
        else
          listed+="  $p: $(printf '%s\n' "$found" | wc -l | tr -d ' ') string(s) of the executable, e.g. $(printf '%s\n' "$found" | head -3 | cut -c1-90 | sed 's/.*/"&"/' | paste -sd' ' -)"$'\n'
        fi
      else
        bad_content+="$hit holds $p; "
      fi
    done <<< "$hits"
  done
  if [ -n "$bad_content" ]; then result content FAIL "$bad_content"
  else result content PASS "no game file; the disc image's SHA-256 ($iso_sha...) in no file; hits only in the executable's own strings:"; fi
  [ -n "$listed" ] && printf '%s' "$listed"

  # setup: the installer from the disc image into DIR/data.
  local data="$dir/data" rc copied iso_size installed=no
  rm -rf "$data" "$dir/shots" "$dir/finder_shots"
  mkdir -p "$data" "$dir/shots" "$dir/finder_shots"
  run_bounded 300 "$dir/setup.log" env ${CLEAN_ENV[@]+"${CLEAN_ENV[@]}"} PURE_DATA_DIR="$data" "$EXE" --install "$iso"
  rc=$?
  iso_size=$(stat -L -f %z "$iso")
  copied=no
  [ -f "$data/disc.iso" ] && [ ! -L "$data/disc.iso" ] && [ "$(stat -f %z "$data/disc.iso")" = "$iso_size" ] && copied=yes
  if [ $rc -eq 0 ] && [ -f "$data/EBOOT.ELF" ] && [ -f "$data/settings.ini" ] && [ $copied = yes ]; then
    installed=yes
    result setup PASS "exit 0, image copied ($iso_size bytes), data directory $(du -sk "$data" | cut -f1) KiB: $(ls "$data" | paste -sd' ' -)"
  else
    result setup FAIL "exit $rc, copied $copied, data: $(ls "$data" | paste -sd' ' -); $(grep -v '%' "$dir/setup.log" | tail -1) (log $dir/setup.log)"
  fi

  # route and finder play the installed game: nothing to play without it (the setup screens would wait for a click).
  local script
  script=$(route_script)
  if [ $installed = yes ]; then
    # Silent (task 034's follow-up, task 042): the runs play the installation with the in-game menu's Mute on,
    # audio.mute=1 in DIR/data/settings.ini, which the app reads from PURE_DATA_DIR (the environment has no variable
    # for it, so `open --env` could not pass it). The audio sink still opens the device, at gain 0, as a player's app
    # does with Mute on. The setup wrote the file without the key; of two lines with one key the later one counts.
    printf 'audio.mute=1\n' >> "$data/settings.ini"
    echo "silent: audio.mute=1 in $data/settings.ini for route and finder"
    route_check "$dir" "$data" "$script"
    finder_check "$dir" "$data" "$script"
    prewarm_check "$dir"
  else
    result route FAIL "not run: no installation in $data (setup failed)"
    result finder FAIL "not run: no installation in $data (setup failed)"
    result prewarm FAIL "not run: no installation in $data (setup failed)"
  fi

  # The bundle's files.
  (cd "$STAGE" && find "$NAME.app" -type f -exec stat -f '%z %N' {} + | sort -k2) > "$dir/bundle_files.txt"
  echo
  echo "files of $NAME.app (bytes, path; $dir/bundle_files.txt), $(du -sh "$APP" | cut -f1) in all:"
  awk '{ size = $1; $1 = ""; printf "%10d %s\n", size, substr($0, 2) }' "$dir/bundle_files.txt"
  echo "data directory after setup: $(du -sh "$data" | cut -f1) ($(ls "$data" | paste -sd' ' -))"
  echo
  if [ $FAILED -eq 0 ]; then echo "bundle check: PASS"; exit 0; fi
  echo "bundle check: FAIL ($FAILED checks)"
  exit 1
}

case "${1:-}" in
  --check) [ $# -eq 2 ] || usage; check "$2" ;;
  -h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
  *) [ $# -le 1 ] || usage; pack "${1:-}" ;;
esac
