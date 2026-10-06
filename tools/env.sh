# Source this (or let tools/* source it) before building anything in pure-recomp.
export CC=/usr/bin/clang
export CXX=/usr/bin/clang++
export PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH"
export CCACHE_DIR="${CCACHE_DIR:-$HOME/dev/pure-recomp/.ccache}"   # the main checkout's, shared by every worktree
export HOMEBREW_NO_AUTO_UPDATE=1
export PURE_ROOT="${PURE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
# Worktrees share one cache: with a base dir, ccache rewrites absolute paths under the checkout so an object compiled
# in ~/dev/pure-recomp is a hit in /tmp/pure-wt (the corpus is 144 units, 8 minutes cold).
export CCACHE_BASEDIR="$PURE_ROOT"
export CCACHE_NOHASHDIR=1
export GHIDRA_HOME="${GHIDRA_HOME:-$(/opt/homebrew/bin/brew --prefix ghidra 2>/dev/null)/libexec}"
# PURE_MALLOC_DEBUG=1 (task 015): macOS's malloc checks for the game runs started from this shell. Freed blocks are
# filled with 0x55 (MallocScribble), so a write or a free through a dangling pointer usually fails on the spot, in the
# guilty call, instead of damaging a free list that is only noticed later; new blocks are filled with 0xAA, large
# blocks get guard pages, and the heap is checked every 1000 operations (aborting, so a crash report has the stack).
# Every program the shell starts inherits them, the compiler too, so scope it to the run with a subshell:
#   (PURE_MALLOC_DEBUG=1 . tools/env.sh; tools/run_boot.py --script out/x/route.txt --frames N out/x/run.log)
# A race to frame 6045 runs at about its normal speed with all of them on.
if [ "${PURE_MALLOC_DEBUG:-0}" != 0 ]; then
  export MallocScribble=1 MallocPreScribble=1 MallocGuardEdges=1
  export MallocCheckHeapStart=1000 MallocCheckHeapEach=1000 MallocCheckHeapAbort=1
fi
