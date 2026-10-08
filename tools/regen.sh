#!/bin/bash
# Regenerate the AOT corpus from the game's executable into generated/ (never committed), then rebuild.
# Analyzer report goes to out/analysis/. Codegen takes about 85 s; the compile of 144 units 15-20 minutes.
set -e
cd "$(dirname "$0")/.." && . tools/env.sh
case "$(uname -s)" in MINGW*|MSYS*) B=build/win-x64; TIME= ;; *) B=build/arm64; TIME="/usr/bin/time -l" ;; esac
ELF=game/EBOOT.ELF
[ -f "$ELF" ] || { echo "missing $ELF (tools/setup_game.sh)"; exit 1; }
tools/build.sh tools
mkdir -p out/analysis generated
$B/portablekit/psp_analyze "$ELF" out/analysis/report.json 0x08804000 2>&1 | tail -3
$TIME $B/portablekit/psp_recomp "$ELF" --auto generated 0x08804000 > out/analysis/codegen.stdout 2> out/analysis/codegen.stderr || { tail -5 out/analysis/codegen.stderr; exit 1; }
echo "generated: $(ls generated/*.cpp | wc -l | tr -d ' ') units, $(du -sh generated | cut -f1)"
grep -ho 'unsupported(0x[0-9A-Fa-f]*u, 0x[0-9A-Fa-f]*u, "[^"]*"' generated/generated_unit_*.cpp | sed 's/.*"\(.*\)"/\1/' | sort | uniq -c | sort -rn | tee out/analysis/unsupported.txt
[ "${1:-}" = "--no-build" ] || { cmake --preset "$(basename $B)" > /dev/null; tools/build.sh profile; }
