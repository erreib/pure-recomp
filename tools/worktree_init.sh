#!/bin/bash
# First thing in a fresh git worktree: makes it buildable in about a minute, without regenerating or recompiling
# the corpus.
#   1. tools/vendor_setup.sh: the pinned framework in vendor/portablekit with patches/ applied. Skipped when
#      tools/patches.sh check already passes; refused when the vendor tree holds changes the series does not cover.
#   2. Links into the main checkout (the first entry of `git worktree list`, or $PURE_MAIN_CHECKOUT): disc/ and
#      generated/ (the corpus: never regenerated in a worktree), disc.iso to the image the main checkout names, and
#      each git-ignored entry of the main checkout's ref/ (the PPSSPP references) into this worktree's ref/.
#      On Windows (Git Bash, no symlinks without Developer Mode; task 055) directories are junctions
#      (`mklink /J`, no privilege needed) and files hard links (the worktree is on the main checkout's volume);
#      Git Bash's `ln -s` would silently copy instead. A junction or hard link into ref/ shares the main
#      checkout's references: a retake in the worktree writes them there.
#   3. tools/setup_game.sh: game/ of this worktree's own (EBOOT.ELF, disc.iso link, and its own ms0/ saves).
#   4. The FFmpeg archive from the main checkout's build directory, so configure does not download it again
#      (macOS: the source tarball, cloned on APFS; Windows: BtbN's prebuilt zip, copied).
#   5. tools/build.sh profile with the shared CCACHE_DIR of tools/env.sh, so the 144 corpus units are cache hits.
#      Prints the build time and how the ccache hit and miss counts moved (the cache is shared, so a build running
#      in another worktree at the same time shows up in them too). The build log is out/worktree_init.log.
set -e
cd "$(dirname "$0")/.."
export PURE_ROOT="$PWD"   # not a PURE_ROOT inherited from a shell set up in another checkout
. tools/env.sh
t0=$SECONDS
case "$(uname -s)" in MINGW*|MSYS*) WIN=1; PRESET=win-x64; EXE=PureNative.exe ;; *) WIN=; PRESET=arm64; EXE=PureNative ;; esac

main="${PURE_MAIN_CHECKOUT:-$(git worktree list --porcelain | sed -n '1s/^worktree //p')}"
[ -d "$main" ] || { echo "main checkout not found: '$main' (set PURE_MAIN_CHECKOUT)"; exit 1; }
main=$(cd "$main" && pwd -P)
[ "$main" != "$(pwd -P)" ] || { echo "this is the main checkout; tools/worktree_init.sh is for worktrees"; exit 1; }
echo "worktree $PWD"
echo "main     $main"

# 1. Vendor tree.
if [ -d vendor/portablekit/.git ] && [ -s vendor/PIN ]; then
  if ! tools/patches.sh check; then
    echo "vendor/portablekit is not the pin plus patches/. tools/vendor_setup.sh would reset it: export your change"
    echo "first (tools/patches.sh export NNNN-slug), or run tools/vendor_setup.sh yourself to discard it."
    exit 1
  fi
else
  tools/vendor_setup.sh
fi

# 2. Links into the main checkout.
link() {   # link NAME TARGET
  if [ -n "$WIN" ]; then
    # Git Bash reports a junction as a symlink (-L); a hard link is a plain file, kept when it is the same file.
    if [ -L "$1" ] && [ -d "$2" ]; then MSYS_NO_PATHCONV=1 cmd /c rmdir "$(cygpath -w "$1")" > /dev/null
    elif [ -f "$1" ] && [ "$1" -ef "$2" ]; then echo "  keep  $1 (hard link to $2)"; return
    elif [ -e "$1" ] || [ -L "$1" ]; then echo "  keep  $1 (a real file or directory in this worktree)"; return; fi
    if [ -d "$2" ]; then MSYS_NO_PATHCONV=1 cmd /c mklink /J "$(cygpath -w "$1")" "$(cygpath -w "$2")" > /dev/null
    else ln "$2" "$1"; fi
    echo "  link  $1 -> $2"
    return
  fi
  if [ -L "$1" ]; then ln -sfn "$2" "$1"
  elif [ -e "$1" ]; then echo "  keep  $1 (a real file or directory in this worktree)"; return
  else ln -s "$2" "$1"; fi
  echo "  link  $1 -> $2"
}
[ -d "$main/disc/PSP_GAME" ] || { echo "$main/disc is not extracted (tools/iso_extract.py there)"; exit 1; }
[ -d "$main/generated" ] || { echo "$main/generated is missing: the corpus is generated in the main checkout only"; exit 1; }
if [ -L "$main/disc.iso" ]; then
  iso=$(readlink "$main/disc.iso")
  case "$iso" in /*) ;; *) iso="$main/$iso" ;; esac
else
  iso="$main/disc.iso"
fi
link disc "$main/disc"
link generated "$main/generated"
link disc.iso "$iso"
[ -e disc.iso ] || { echo "disc.iso dangles: $iso. Stop here; do not look for the image elsewhere."; exit 1; }
# ref/: README.md is tracked; the references are git-ignored and live in the main checkout.
if [ -d "$main/ref" ]; then
  n=0
  for r in "$main/ref"/*; do
    [ -e "$r" ] && [ "${r##*/}" != README.md ] || continue
    link "ref/${r##*/}" "$r" > /dev/null; n=$((n + 1))
  done
  echo "  ref:    $n entries of $main/ref linked"
fi
units=$(find -L generated -maxdepth 1 -name 'generated_unit_*.cpp' | wc -l | tr -d ' ')
echo "  corpus: $units units in generated/"

# 3. game/ for the runtime.
tools/setup_game.sh

# 4. FFmpeg archive, cloned (APFS) rather than downloaded; on Windows the prebuilt zip, a plain copy.
dl=build/$PRESET/_deps/downloads
for a in "$main/$dl"/ffmpeg-*.tar.xz "$main/$dl"/ffmpeg-*.zip; do
  [ -f "$a" ] && [ ! -f "$dl/${a##*/}" ] || continue
  mkdir -p "$dl" && { cp -c "$a" "$dl/" 2>/dev/null || cp "$a" "$dl/"; } && echo "  copy  $dl/${a##*/}"
done

# 5. Build.
count() { ccache --print-stats | tr -d '\r' | awk -v k="$1" '$1 == k { print $2 }'; }
hits() { echo $(( $(count direct_cache_hit) + $(count preprocessed_cache_hit) )); }
h0=$(hits); m0=$(count cache_miss)
mkdir -p out
b0=$SECONDS
if ! tools/build.sh profile > out/worktree_init.log 2>&1; then
  tail -30 out/worktree_init.log; echo "build failed (out/worktree_init.log)"; exit 1
fi
build=$(( SECONDS - b0 ))
dh=$(( $(hits) - h0 )); dm=$(( $(count cache_miss) - m0 ))
tail -1 out/worktree_init.log
[ -x build/$PRESET/bin/$EXE ] || { echo "build/$PRESET/bin/$EXE missing after the build"; exit 1; }
echo "ccache: +$dh hits, +$dm misses (the corpus is $units units)"
if [ "$dm" -gt 20 ]; then
  echo "WARNING: $dm cache misses; the corpus did not come from the shared cache. Report the build time; do not"
  echo "change build flags to fix it."
fi
echo "build time: ${build}s (worktree ready in $(( SECONDS - t0 ))s)"
