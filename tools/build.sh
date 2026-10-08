#!/bin/bash
# tools/build.sh configure | tools | profile | all | release | clean
#   configure  cmake configure with the arm64 preset (first run downloads and builds FFmpeg 7.1.5, minutes)
#   tools      psp_analyze, psp_recomp, dump_function (seconds)
#   profile    PureNative: the host layer plus our profile plus whatever corpus is in generated/ (incremental)
#   all        configure + tools + profile
#   release    PureNative in build/release with the arm64-release preset (Release, PORTABLEKIT_RELEASE=ON, bundled
#              FFmpeg in build/release/bin/lib), what tools/bundle.sh packs; the corpus compiles again in Release
#              (10 to 20 minutes cold, run it in the background), incremental after that
set -e
cd "$(dirname "$0")/.." && . tools/env.sh
# The preset by platform: arm64 on macOS, win-x64 on Windows under Git Bash (task 054). Jobs: one generated unit
# per 4 GiB, as the framework recommends, capped at the hardware threads.
case "$(uname -s)" in
MINGW*|MSYS*)
  PRESET=win-x64
  JOBS="${JOBS:-$(( $(wmic computersystem get TotalPhysicalMemory 2>/dev/null | grep -o '[0-9]*' || echo 17179869184) / 4294967296 ))}"
  [ "$JOBS" -gt "${NUMBER_OF_PROCESSORS:-4}" ] && JOBS="${NUMBER_OF_PROCESSORS:-4}"
  ;;
*)
  PRESET=arm64
  JOBS="${JOBS:-$(( $(sysctl -n hw.memsize) / 4294967296 ))}"
  ;;
esac
B=build/$PRESET
[ "$JOBS" -lt 2 ] && JOBS=2
configure() { cmake --preset $PRESET "$@"; }
release() {
  local R=build/release archive=_deps/downloads/ffmpeg-7.1.5.tar.xz
  if [ ! -f $R/build.ninja ]; then
    # The FFmpeg archive the developer build already downloaded (cmake/FFmpeg.cmake checks its SHA-256 either way).
    if [ -f $B/$archive ] && [ ! -f $R/$archive ]; then mkdir -p "$(dirname $R/$archive)"; cp $B/$archive $R/$archive; fi
    cmake --preset arm64-release
  fi
  cmake --build $R --target PureNative -j "$JOBS"
}
case "${1:-profile}" in
  configure) configure "${@:2}" ;;
  tools)     [ -f $B/build.ninja ] || configure; cmake --build $B --target psp_analyze psp_recomp dump_function -j "$JOBS" ;;
  profile)   [ -f $B/build.ninja ] || configure; cmake --build $B --target PureNative -j "$JOBS" ;;
  all)       configure; cmake --build $B --target psp_analyze psp_recomp dump_function PureNative -j "$JOBS" ;;
  release)   release ;;
  clean)     cmake --build $B --target clean ;;
  *) sed -n '2,10p' "$0"; exit 2 ;;
esac
