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
