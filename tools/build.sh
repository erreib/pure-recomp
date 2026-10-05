#!/bin/bash
# tools/build.sh configure | tools | profile | all | clean
#   configure  cmake configure with the arm64 preset (first run downloads and builds FFmpeg 7.1.5, minutes)
#   tools      psp_analyze, psp_recomp, dump_function (seconds)
#   profile    PureNative: the host layer plus our profile plus whatever corpus is in generated/ (incremental)
#   all        configure + tools + profile
set -e
cd "$(dirname "$0")/.." && . tools/env.sh
B=build/arm64
JOBS="${JOBS:-$(( $(sysctl -n hw.memsize) / 4294967296 ))}"   # one generated unit per 4 GiB, as the framework recommends
[ "$JOBS" -lt 2 ] && JOBS=2
configure() { cmake --preset arm64 "$@"; }
case "${1:-profile}" in
  configure) configure "${@:2}" ;;
  tools)     [ -f $B/build.ninja ] || configure; cmake --build $B --target psp_analyze psp_recomp dump_function -j "$JOBS" ;;
  profile)   [ -f $B/build.ninja ] || configure; cmake --build $B --target PureNative -j "$JOBS" ;;
  all)       configure; cmake --build $B --target psp_analyze psp_recomp dump_function PureNative -j "$JOBS" ;;
  clean)     cmake --build $B --target clean ;;
  *) sed -n '2,7p' "$0"; exit 2 ;;
esac
