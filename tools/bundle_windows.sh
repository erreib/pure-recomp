#!/bin/bash
# tools/bundle_windows.sh [--zip]      pack the Windows release folder "Wipeout Pure" (task 061, docs/release.md "Windows")
# tools/bundle_windows.sh --check DIR  check the packed folder (below); exit 0 when every check passes
#
# Git Bash on Windows, like the other tools. The framework has no Windows packer for a game
# (vendor/portablekit/scripts/package_desktop_windows.ps1 packs the desktop app and its toolchain), so this is ours,
# shaped after tools/bundle.sh and that script's checks (no game data, no path of this machine, the packed program runs).
#
# Packing: tools/build.sh release when build/release-win/bin/PureNative.exe is missing or older than the sources (the
# first time 15 to 25 minutes: the corpus compiles again in Release), then out/release-windows/stage/Wipeout Pure/:
#   Wipeout Pure.exe     PureNative.exe of the win-x64-release preset (Release, PORTABLEKIT_RELEASE=ON, the static C
#                        runtime, the windows subsystem: no console window when started from Explorer)
#   SDL3.dll avcodec-61.dll avutil-59.dll swresample-5.dll   the DLLs the build put beside it
#   LICENSE.txt          ours (GPL-2.0-or-later); README.txt from packaging/windows/README.txt
#   BUILDINFO.txt        the version, the commit, the toolchain and the pins
#   licenses/            FFmpeg-LICENSE.txt and FFmpeg-SOURCE.txt (the build's), PortableKit's, SDL3's, Dear ImGui's,
#                        tiny-AES-c's and xxHash's licences, and packaging/THIRD_PARTY_NOTICES.md
# The version is CMakeLists.txt's project version and the commit, 0.1.0-<hash>[-dirty].
#   --zip   also out/release-windows/dist/pure-recomp-<version>-windows-x64.zip (Windows' own tar.exe -a), SHA256SUMS
#           and BUILDINFO.txt
#
# --check DIR (task 061's Verify line; packs first when the stage is missing; DIR/data and DIR/shots are made afresh,
# nothing outside DIR is written):
#   files    the folder holds exactly the names above (listed with their sizes in DIR/bundle_files.txt)
#   dlls     every DLL the executable and each bundled DLL imports (llvm-objdump -p) is beside it in the folder or a
#            system DLL: an api-ms-win-*/ext-ms-* API set, or a DLL of System32 that is not a redistributable C/C++
#            runtime (vcruntime*, msvcp*, concrt*, vccorlib*, ucrtbased*); vulkan-1.dll is the driver's loader
#   machine  no path of this machine (H:/errei, C:/Users/<user> in either slash, the user name) in any file
#   names    no file named like game data (tools/bundle.sh's names and packaging/release.env's RELEASE_GAME_NAMES)
#   content  no file holds a disc image (CD001 at 32769), a PSP executable (MIPS ELF, ~PSP), a PBP or a PARAM.SFO; the
#            strings UCUS98612, .iso, .wad, EBOOT, BOOT.BIN and the disc image's SHA-256 prefix are in no file but the
#            executable, and there only inside its own text strings (listed), and the two read-me texts this
#            repository writes (README.txt, licenses/THIRD_PARTY_NOTICES.md: they name the disc image and the data
#            folder's files to the player; their lines are listed), or in a bundled DLL only inside longer words
#            (avcodec-61.dll's RESIDUEBOOTSTRAP_...: listed); the SHA-256 prefix is in no file at all
#   setup    the staged executable with PURE_DATA_DIR=DIR/data and --install <the image disc.iso is> (no other PURE_
#            variable): exit 0, DIR/data holds EBOOT.ELF, settings.ini and the copied disc.iso (as big as the image)
#   route    the staged executable again with only PURE_DATA_DIR and the route's variables (PURE_INPUT_SCRIPT from
#            config/pad_scripts/frontend.txt, PURE_SCREENSHOT_DIR=DIR/shots with PURE_SCREENSHOT_EVERY=0,
#            PURE_EXIT_AT_FRAME=2200), the default shell and backend (Vulkan, windowed): it plays the installed game,
#            reaches frame 2200, and DIR/shots/title.png is within tol 24, max-frac 0.05 of ref/title.png
# route needs the installation: when setup fails it is reported FAIL without running. It runs silent: after the setup
# DIR/data/settings.ini gets audio.mute=1 (the in-game menu's Mute), as tools/bundle.sh does.
# Not here, macOS only (tools/bundle.sh): bundle (codesign), finder (LaunchServices) and prewarm (the Metal backend's
# pre-warm list, config/metal_pipelines.txt; the Vulkan path has its pipeline cache in the data directory instead).
set -u
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"
. tools/env.sh
ROOT=$PWD
case "$(uname -s)" in MINGW*|MSYS*) ;; *) echo "bundle_windows: Windows only (Git Bash); the Mac app is tools/bundle.sh"; exit 2 ;; esac

# shellcheck disable=SC1091
. packaging/release.env
NAME=$RELEASE_NAME
BUILD=build/release-win
OUT=out/release-windows
STAGE=$OUT/stage
DIST=$OUT/dist
FOLDER="$ROOT/$STAGE/$NAME"
EXE="$FOLDER/$NAME.exe"
DLLS="SDL3.dll avcodec-61.dll avutil-59.dll swresample-5.dll"
LICENSES="FFmpeg-LICENSE.txt FFmpeg-SOURCE.txt PortableKit-LICENSE.txt SDL3-LICENSE.txt DearImGui-LICENSE.txt
tiny-AES-c-UNLICENSE.txt xxHash-LICENSE.txt THIRD_PARTY_NOTICES.md"
DOCS="README.txt licenses/THIRD_PARTY_NOTICES.md"   # our own texts for the player (the content check lists their hits)
TITLE_TOL=24
TITLE_MAX_FRAC=0.05
ROUTE_FRAMES=2200

usage() { sed -n '2,3p' "$0"; exit 2; }

expected_files() {   # the folder's files, sorted
  { printf '%s\n' "$NAME.exe" LICENSE.txt README.txt BUILDINFO.txt
    for f in $DLLS; do printf '%s\n' "$f"; done
    for f in $LICENSES; do printf 'licenses/%s\n' "$f"; done; } | LC_ALL=C sort
}

version() { printf '%s-%s' "$(sed -n 's/^project(PureRecomp VERSION \([0-9.]*\).*/\1/p' CMakeLists.txt)" "$(git describe --always --dirty)"; }

disc_image() {   # Erik's disc image: where disc.iso points; on Windows disc.iso is a hard link to it (docs/setup.md)
  local target
  if [ -L disc.iso ]; then
    target=$(readlink disc.iso)
    case "$target" in /*) ;; *) target="$ROOT/$target" ;; esac
  else
    target="$ROOT/disc.iso"
  fi
  [ -f "$target" ] && [ -s "$target" ] || { echo "disc.iso dangles: $target. Stop here; do not look for the image elsewhere." >&2; return 1; }
  printf '%s\n' "$target"
}

# ---------------------------------------------------------------------------------------------------------------------
stage() {
  local newer sdl_root v
  if [ ! -f $BUILD/bin/PureNative.exe ]; then
    echo "== $BUILD/bin/PureNative.exe is missing: tools/build.sh release (15 to 25 minutes the first time)"
    tools/build.sh release || exit 1
  else
    newer=$(find src config patches CMakeLists.txt CMakePresets.json generated/ vendor/portablekit/host \
              vendor/portablekit/src vendor/portablekit/include vendor/portablekit/cmake \
              vendor/portablekit/CMakeLists.txt third_party -type f ! -path config/metal_pipelines.txt \
              -newer $BUILD/bin/PureNative.exe 2>/dev/null | head -1)
    if [ -n "$newer" ]; then
      echo "== $BUILD/bin/PureNative.exe is older than $newer: tools/build.sh release"
      tools/build.sh release || exit 1
    else
      echo "== $BUILD/bin/PureNative.exe is up to date"
    fi
  fi
  sdl_root=$(sed -n 's/^SDL3_ROOT:[A-Z]*=//p' $BUILD/CMakeCache.txt | tr -d '\r')
  [ -f "$sdl_root/LICENSE.txt" ] || { echo "bundle_windows: no SDL3 licence at '$sdl_root/LICENSE.txt' (SDL3_ROOT)"; exit 1; }
  v=$(version)
  echo "== staging $NAME $v in $STAGE/$NAME"
  rm -rf "$STAGE"
  mkdir -p "$FOLDER/licenses"
  cp "$BUILD/bin/PureNative.exe" "$EXE" || exit 1
  for f in $DLLS; do cp "$BUILD/bin/$f" "$FOLDER/" || exit 1; done
  cp LICENSE "$FOLDER/LICENSE.txt"
  cp packaging/windows/README.txt "$FOLDER/README.txt"
  cp "$BUILD/bin/FFmpeg-LICENSE.txt" "$BUILD/bin/FFmpeg-SOURCE.txt" "$FOLDER/licenses/" || exit 1
  cp vendor/portablekit/LICENSE "$FOLDER/licenses/PortableKit-LICENSE.txt"
  cp "$sdl_root/LICENSE.txt" "$FOLDER/licenses/SDL3-LICENSE.txt"
  cp vendor/portablekit/third_party/imgui/LICENSE.txt "$FOLDER/licenses/DearImGui-LICENSE.txt"
  cp vendor/portablekit/third_party/tiny_aes/UNLICENSE "$FOLDER/licenses/tiny-AES-c-UNLICENSE.txt"
  cp vendor/portablekit/third_party/xxhash/LICENSE "$FOLDER/licenses/xxHash-LICENSE.txt"
  cp packaging/THIRD_PARTY_NOTICES.md "$FOLDER/licenses/"
  {
    printf '%s %s for Windows x64\r\n' "$NAME" "$v"
    printf 'Built from: pure-recomp %s\r\n' "$(git rev-parse HEAD)"
    printf 'PortableKit: %s with patches/ %s\r\n' "$(tr -d '\r\n' < vendor/PIN | cut -c1-40)" \
      "$(ls patches/*.patch | sed 's#.*/##; s/-.*//' | sed -n '1p;$p' | paste -sd- -)"
    printf 'Toolchain: %s, lld-link; preset win-x64-release (Release, PORTABLEKIT_RELEASE=ON, static C runtime, windows subsystem)\r\n' \
      "$(clang-cl --version | head -1 | tr -d '\r')"
    printf 'Shipped: SDL3 3.4.18 (libsdl-org prebuilt SDL3.dll); FFmpeg 7.1.5 LGPL shared build of BtbN/FFmpeg-Builds (licenses/FFmpeg-SOURCE.txt)\r\n'
  } > "$FOLDER/BUILDINFO.txt"
  echo "stage: $STAGE/$NAME ($(du -sh "$FOLDER" | cut -f1))"
}

pack() {
  local zip=no v archive
  case "${1:-}" in --zip) zip=yes ;; "") ;; *) usage ;; esac
  stage
  if [ $zip = yes ]; then
    v=$(version)
    archive="$RELEASE_SLUG-$v-windows-x64.zip"
    rm -rf "$DIST"; mkdir -p "$DIST"
    # Windows' own tar (bsdtar) writes zip archives (-a by the suffix); Git Bash's GNU tar comes first on PATH.
    "$SYSTEMROOT/System32/tar.exe" -a -c -f "$(cygpath -w "$ROOT/$DIST/$archive")" -C "$(cygpath -w "$ROOT/$STAGE")" "$NAME" ||
      { echo "bundle_windows: tar.exe could not write $DIST/$archive"; exit 1; }
    (cd "$DIST" && sha256sum "$archive" | sed 's/ \*/  /' > SHA256SUMS)
    cp "$FOLDER/BUILDINFO.txt" "$DIST/"
    ls -l "$DIST" | tail -n +2 | awk '{ printf "dist: %s/%s (%s bytes)\n", "'"$DIST"'", $NF, $5 }'
    cat "$DIST/SHA256SUMS"
  fi
  exit 0
}

# ---------------------------------------------------------------------------------------------------------------------
FAILED=0
result() {   # result NAME PASS|FAIL DETAIL
  printf '%-8s %s  %s\n' "$1" "$2" "$3"
  [ "$2" = PASS ] || FAILED=$((FAILED + 1))
}

# Runs a command with stdout and stderr in LOG, killed (the whole tree, by its Windows pid) after SECONDS; the
# command's exit status, 124 on the deadline.
run_bounded() {
  local seconds=$1 log=$2 pid winpid ticks=0
  shift 2
  "$@" > "$log" 2>&1 < /dev/null &
  pid=$!
  while kill -0 $pid 2> /dev/null; do
    if [ $ticks -ge $((seconds * 10)) ]; then
      winpid=$(cat /proc/$pid/winpid 2> /dev/null)
      [ -n "$winpid" ] && taskkill //F //T //PID "$winpid" > /dev/null 2>&1
      kill -9 $pid 2> /dev/null
      wait $pid 2> /dev/null
      echo "[bundle] deadline: killed after $seconds s" >> "$log"
      return 124
    fi
    sleep 0.1
    ticks=$((ticks + 1))
  done
  wait $pid
}

# The environment the program runs with: no PURE_ variable of this shell.
CLEAN_ENV=()
for var in $(env | sed -n 's/^\(PURE_[A-Za-z0-9_]*\)=.*/\1/p'); do CLEAN_ENV+=(-u "$var"); done

route_script() {   # the route's steps joined with ';' as tools/run_boot.py does
  grep -Ev '^[[:space:]]*(#|$)' config/pad_scripts/frontend.txt | tr -d '\r' | paste -sd';' -
}

bmp_to_png() {
  python3 - "$(cygpath -m "$1")" <<'PY'
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

inside_words() {   # inside_words STRING FILE: yes when every occurrence of STRING in FILE has a word character on both sides
  local re all inside
  re=$(printf '%s' "$1" | sed 's/\./\\./g')
  all=$(LC_ALL=C grep -aoF -- "$1" "$2" | wc -l)
  inside=$(LC_ALL=C grep -aoE -- "[A-Za-z0-9_]${re}[A-Za-z0-9_]" "$2" | wc -l)
  [ "$all" -gt 0 ] && [ "$all" = "$inside" ] && echo yes || echo no
}

norm() { tr '\\' '/' | tr '[:upper:]' '[:lower:]'; }   # a Windows path as the log prints it, for comparing

route_check() {   # route_check DIR DATA SCRIPT
  local dir=$1 data=$2 script=$3 rc line exe_line disc_line render_line want_exe want_disc
  run_bounded 240 "$dir/route.log" env ${CLEAN_ENV[@]+"${CLEAN_ENV[@]}"} PURE_DATA_DIR="$(cygpath -m "$data")" \
    PURE_INPUT_SCRIPT="$script" PURE_SCREENSHOT_DIR="$(cygpath -m "$dir/shots")" PURE_SCREENSHOT_EVERY=0 \
    PURE_EXIT_AT_FRAME=$ROUTE_FRAMES "$EXE"
  rc=$?
  bmp_to_png "$dir/shots"
  render_line=$(grep -m1 -a '^Renderer: Vulkan' "$dir/route.log" | tr -d '\r' || true)
  exe_line=$(grep -m1 -a '^Executable: ' "$dir/route.log" | tr -d '\r' || true)
  disc_line=$(grep -m1 -a '^Disc image: ' "$dir/route.log" | tr -d '\r' || true)
  want_exe=$(printf 'Executable: %s/EBOOT.ELF' "$(cygpath -m "$data")" | norm)
  want_disc=$(printf 'Disc image: %s/disc.iso' "$(cygpath -m "$data")" | norm)
  if ! grep -qa "^\[pure\] exit at frame $ROUTE_FRAMES" "$dir/route.log"; then
    result route FAIL "exit $rc, frame $ROUTE_FRAMES not reached (log $dir/route.log)"
  elif [ "$(printf '%s' "$exe_line" | norm)" != "$want_exe" ] || [ "$(printf '%s' "$disc_line" | norm)" != "$want_disc" ]; then
    result route FAIL "not the installed game: '$exe_line', '$disc_line'"
  elif [ -z "$render_line" ]; then
    result route FAIL "not the Vulkan renderer in a window (log $dir/route.log)"
  elif [ ! -f "$dir/shots/title.png" ]; then
    result route FAIL "no title shot in $dir/shots"
  else
    line=$(python3 tools/imgdiff.py "$(cygpath -m "$dir/shots/title.png")" ref/title.png --tol $TITLE_TOL --max-frac $TITLE_MAX_FRAC 2>&1)
    if [ $? -eq 0 ]; then result route PASS "exit $rc (4: the runtime stopped, by PURE_EXIT_AT_FRAME) at frame $ROUTE_FRAMES from DIR/data, $render_line; title: $line"
    else result route FAIL "title: $line"; fi
  fi
}

check() {
  local dir=$1 iso iso_sha
  [ -f ref/title.png ] || { echo "ref/title.png missing (tools/worktree_init.sh links the main checkout's ref/)"; exit 2; }
  iso=$(disc_image) || exit 2
  if [ ! -f "$EXE" ]; then echo "== no $STAGE/$NAME: packing first"; stage; fi
  mkdir -p "$dir"
  dir=$(cd "$dir" && pwd)
  echo "bundle_windows check $(date '+%Y-%m-%d %H:%M'): $STAGE/$NAME, data $dir/data"

  # files: exactly the expected names.
  local have want
  (cd "$FOLDER" && find . -type f -printf '%s %P\n' | LC_ALL=C sort -k2) > "$dir/bundle_files.txt"
  have=$(cut -d' ' -f2- "$dir/bundle_files.txt")
  want=$(expected_files)
  if [ "$have" = "$want" ]; then
    result files PASS "$(printf '%s\n' "$have" | wc -l | tr -d ' ') files, as expected ($dir/bundle_files.txt)"
  else
    result files FAIL "$(diff <(printf '%s\n' "$want") <(printf '%s\n' "$have") | grep '^[<>]' | sed 's/^</missing/; s/^>/extra/' | paste -sd';' -)"
  fi

  # dlls: every import beside the program or the system's.
  local f dll bad_dlls="" sys32 lower system_used=""
  sys32="$SYSTEMROOT/System32"
  while IFS= read -r f; do
    while IFS= read -r dll; do
      [ -n "$dll" ] || continue
      lower=$(printf '%s' "$dll" | tr '[:upper:]' '[:lower:]')
      if [ -f "$FOLDER/$dll" ]; then continue; fi
      case "$lower" in
        api-ms-win-*|ext-ms-*) continue ;;
        vcruntime*|msvcp*|concrt*|vccorlib*|ucrtbased*) bad_dlls+="$(basename "$f"): $dll (a C/C++ runtime redistributable); "; continue ;;
      esac
      if [ -f "$sys32/$dll" ]; then
        case " $system_used " in *" $lower "*) ;; *) system_used+=" $lower" ;; esac
      else
        bad_dlls+="$(basename "$f"): $dll (not beside it, not in System32); "
      fi
    done < <(llvm-objdump -p "$f" | sed -n 's/^ *DLL Name: //p' | tr -d '\r')
  done < <(printf '%s\n' "$EXE"; for d in $DLLS; do printf '%s\n' "$FOLDER/$d"; done)
  if [ -n "$bad_dlls" ]; then result dlls FAIL "$bad_dlls"
  else result dlls PASS "the program and $(printf '%s\n' $DLLS | wc -l | tr -d ' ') DLLs import only each other, API sets and System32's:$system_used"; fi

  # machine: no path of this machine.
  local leaks user=${USERNAME:-$(id -un)}
  leaks=$(LC_ALL=C grep -rlaiF -e 'H:/errei' -e 'H:\errei' -e '/h/errei' -e "C:/Users/$user" -e "C:\\Users\\$user" \
            -e "$user" -e 'dev-stuff' "$FOLDER" || true)
  if [ -n "$leaks" ]; then result machine FAIL "$(printf '%s' "$leaks" | tr '\n' ' ')"
  else result machine PASS "no H:/errei, H:\\errei, C:/Users/$user (either slash), $user or dev-stuff in any file, any case"; fi

  # names: no file named like game data.
  local base pattern bad_names=""
  while IFS= read -r -d '' f; do
    base=$(basename "$f" | tr '[:upper:]' '[:lower:]')
    case "$base" in
      eboot*|*.iso|*.cso|*.pbp|*.prx|*.elf|*.ovl|*.bin|param.sfo|umd_data*|ms0|savedata)
        bad_names+="$f; "; continue ;;
    esac
    set -f
    for pattern in $RELEASE_GAME_NAMES; do
      # shellcheck disable=SC2254
      case "$base" in $pattern) bad_names+="$f; " ;; esac
    done
    set +f
  done < <(find "$FOLDER" -print0)
  if [ -n "$bad_names" ]; then result names FAIL "$bad_names"
  else result names PASS "no file named like game data ($(find "$FOLDER" | wc -l | tr -d ' ') entries)"; fi

  # content: no game file by its header; the game's strings only in the executable's own text and our read-me texts.
  local head bad_content="" strings_file="$dir/exe_strings.txt" hits hit p found listed="" rel doc
  while IFS= read -r -d '' f; do
    head=$(head -c 20 "$f" | od -An -tx1 | tr -d ' \n')
    case "$head" in
      7f454c46*) [ "${head:36:4}" = 0800 ] && bad_content+="$f (PSP executable); " ;;
      00504250*) bad_content+="$f (PBP); " ;;
      7e505350*) bad_content+="$f (encrypted PSP module); " ;;
      00505346*) bad_content+="$f (PARAM.SFO); " ;;
    esac
    if [ "$(stat -c %s "$f")" -gt 32774 ] &&
       [ "$(dd if="$f" bs=1 skip=32769 count=5 2> /dev/null | LC_ALL=C tr -d '\0')" = CD001 ]; then
      bad_content+="$f (disc image); "
    fi
  done < <(find "$FOLDER" -type f -print0)
  iso_sha=$(sha256sum "$iso" | cut -c1-16)
  llvm-strings -n 4 "$EXE" > "$strings_file"
  for p in UCUS98612 .iso .wad EBOOT BOOT.BIN "$iso_sha"; do
    hits=$(LC_ALL=C grep -rlaF -- "$p" "$FOLDER" || true)
    [ -n "$hits" ] || continue
    while IFS= read -r hit; do
      rel=${hit#"$FOLDER/"}
      doc=no
      case " $DOCS " in *" $rel "*) doc=yes ;; esac
      if [ "$p" = "$iso_sha" ]; then
        bad_content+="$rel holds the disc image's SHA-256 prefix; "
      elif [ "$hit" = "$EXE" ]; then
        found=$(LC_ALL=C grep -aF -- "$p" "$strings_file" | LC_ALL=C sort -u)
        if [ -z "$found" ]; then
          bad_content+="executable: $p outside its text strings; "
        else
          listed+="  $p: $(printf '%s\n' "$found" | wc -l | tr -d ' ') string(s) of the executable, e.g. $(printf '%s\n' "$found" | head -3 | cut -c1-90 | sed 's/.*/"&"/' | paste -sd' ' -)"$'\n'
        fi
      elif [[ "$rel" == *.dll ]] && [ "$(inside_words "$p" "$hit")" = yes ]; then
        # A third-party DLL's own identifier that happens to contain the string (BtbN's avcodec carries libvmaf's
        # RESIDUEBOOTSTRAP_LIBSVMNUSVR): every occurrence has a letter, digit or _ on both sides, so it is no name.
        listed+="  $p: $rel, only inside longer words, e.g. \"$(LC_ALL=C grep -aoE "[A-Za-z0-9_]+$(printf '%s' "$p" | sed 's/\./\\./g')[A-Za-z0-9_]+" "$hit" | head -1)\""$'\n'
      elif [ $doc = yes ]; then
        listed+="  $p: $rel, $(LC_ALL=C grep -cF -- "$p" "$hit") line(s), e.g. \"$(LC_ALL=C grep -m1 -F -- "$p" "$hit" | tr -d '\r' | sed 's/^ *//' | cut -c1-80)\""$'\n'
      else
        bad_content+="$rel holds $p; "
      fi
    done <<< "$hits"
  done
  if [ -n "$bad_content" ]; then result content FAIL "$bad_content"
  else result content PASS "no game file; the disc image's SHA-256 ($iso_sha...) in no file; hits only in the executable's own strings and the read-me texts:"; fi
  [ -n "$listed" ] && printf '%s' "$listed"

  # setup: the installer from the disc image into DIR/data.
  local data="$dir/data" rc copied iso_size installed=no
  rm -rf "$data" "$dir/shots"
  mkdir -p "$data" "$dir/shots"
  run_bounded 300 "$dir/setup.log" env ${CLEAN_ENV[@]+"${CLEAN_ENV[@]}"} PURE_DATA_DIR="$(cygpath -m "$data")" \
    "$EXE" --install "$(cygpath -m "$iso")"
  rc=$?
  iso_size=$(stat -c %s "$iso")
  copied=no
  [ -f "$data/disc.iso" ] && ! [ "$data/disc.iso" -ef "$iso" ] && [ "$(stat -c %s "$data/disc.iso")" = "$iso_size" ] && copied=yes
  if [ $rc -eq 0 ] && [ -f "$data/EBOOT.ELF" ] && [ -f "$data/settings.ini" ] && [ $copied = yes ]; then
    installed=yes
    result setup PASS "exit 0, image copied ($iso_size bytes), data directory $(du -sk "$data" | cut -f1) KiB: $(ls "$data" | paste -sd' ' -); setup.log $(wc -l < "$dir/setup.log" | tr -d ' ') lines"
  else
    result setup FAIL "exit $rc, copied $copied, data: $(ls "$data" | paste -sd' ' -); $(grep -av '%' "$dir/setup.log" | tail -1) (log $dir/setup.log)"
  fi

  # route plays the installed game: nothing to play without it (the setup screens would wait for a click).
  if [ $installed = yes ]; then
    printf 'audio.mute=1\n' >> "$data/settings.ini"
    echo "silent: audio.mute=1 in DIR/data/settings.ini for route"
    route_check "$dir" "$data" "$(route_script)"
  else
    result route FAIL "not run: no installation in $data (setup failed)"
  fi

  echo
  echo "files of $STAGE/$NAME (bytes, path; $dir/bundle_files.txt), $(du -sh "$FOLDER" | cut -f1) in all:"
  awk '{ size = $1; $1 = ""; printf "%10d %s\n", size, substr($0, 2) }' "$dir/bundle_files.txt"
  echo "data directory after setup: $(du -sh "$data" | cut -f1) ($(ls "$data" | paste -sd' ' -))"
  echo
  if [ $FAILED -eq 0 ]; then echo "bundle_windows check: PASS"; exit 0; fi
  echo "bundle_windows check: FAIL ($FAILED checks)"
  exit 1
}

case "${1:-}" in
  --check) [ $# -eq 2 ] || usage; check "$2" ;;
  -h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
  *) [ $# -le 1 ] || usage; pack "${1:-}" ;;
esac
