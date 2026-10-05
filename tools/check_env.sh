#!/bin/bash
# Asserts the toolchain this project needs is present and arm64. Exit 0 = ready.
cd "$(dirname "$0")/.." && . tools/env.sh
fail=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }
arch_is_arm64() { file -b "$(command -v "$1" 2>/dev/null || echo /nonexistent)" 2>/dev/null | grep -q arm64; }

echo "pure-recomp environment"
for t in cmake ninja ccache pkg-config python3 glslangValidator; do
  if command -v $t >/dev/null; then
    if arch_is_arm64 $t || file -b "$(command -v $t)" | grep -qi 'script\|text'; then ok "$t ($(command -v $t))"; else bad "$t is not arm64: $(command -v $t)"; fi
  else bad "$t missing"; fi
done
[ "$(/usr/bin/clang --version | head -1 | grep -c 'Apple clang')" = 1 ] && ok "/usr/bin/clang is Apple clang" || bad "/usr/bin/clang is not Apple clang"
for p in sdl3 vulkan; do pkg-config --exists $p 2>/dev/null && ok "pkg-config $p $(pkg-config --modversion $p)" || bad "pkg-config $p missing"; done
[ -e /opt/homebrew/lib/libMoltenVK.dylib ] && ok "MoltenVK" || bad "libMoltenVK.dylib missing"
java -version >/dev/null 2>&1 && ok "java $(java -version 2>&1 | head -1)" || bad "java missing (brew install openjdk@21 via ghidra)"
[ -x "$GHIDRA_HOME/support/analyzeHeadless" ] && ok "ghidra at $GHIDRA_HOME" || bad "ghidra analyzeHeadless missing (GHIDRA_HOME=$GHIDRA_HOME)"
ls ~/opt/ghidra-ext/*ghidra-allegrex*.zip >/dev/null 2>&1 && ok "ghidra-allegrex zip present" || bad "ghidra-allegrex zip missing in ~/opt/ghidra-ext"
{ [ -d /Applications/PPSSPPSDL.app ] || [ -d /Applications/PPSSPP.app ]; } && ok "PPSSPP app ($(ls -d /Applications/PPSSPP*.app | head -1))" || bad "PPSSPP app missing"
if [ -L disc.iso ]; then [ -e disc.iso ] && ok "disc.iso -> $(readlink disc.iso)" || bad "disc.iso symlink dangles: $(readlink disc.iso)"; else bad "disc.iso symlink missing"; fi
[ -f disc/MANIFEST.txt ] && ok "disc/ extracted ($(wc -l < disc/MANIFEST.txt | tr -d ' ') files)" || bad "disc/ not extracted (tools/iso_extract.py disc.iso extract disc)"
[ -d vendor/portablekit ] && [ "$(git -C vendor/portablekit rev-parse HEAD 2>/dev/null)" = "$(cat vendor/PIN 2>/dev/null)" ] && ok "vendor/portablekit at $(cut -c1-7 vendor/PIN)" || bad "vendor/portablekit missing or not at vendor/PIN (tools/vendor_setup.sh)"
exit $fail
