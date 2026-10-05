#!/bin/bash
# Ghidra headless driver for BOOT.BIN.
#   tools/ghidra_headless.sh import     import + auto-analyse BOOT.BIN into ghidra_project/ (slow, once)
#   tools/ghidra_headless.sh export     run tools/ghidra/ExportFunctions.java on the analysed program (fast, repeatable)
#   tools/ghidra_headless.sh script X   run tools/ghidra/X.java with remaining args
set -e
cd "$(dirname "$0")/.." && . tools/env.sh
HL="$GHIDRA_HOME/support/analyzeHeadless"
PROJ_DIR="$PWD/ghidra_project"; PROJ=pure; PROG=BOOT.BIN
ELF="$PWD/disc/PSP_GAME/SYSDIR/BOOT.BIN"
export JAVA_HOME="${JAVA_HOME:-$(/opt/homebrew/bin/brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home}"
export MAXMEM="${MAXMEM:-6G}"
case "$1" in
  import)
    mkdir -p "$PROJ_DIR"
    exec "$HL" "$PROJ_DIR" $PROJ -import "$ELF" -overwrite -processor Allegrex:LE:32:default -loader-imageBase 08804000 \
      -scriptPath "$PWD/tools/ghidra" -log "$PWD/out/ghidra-import.log" ;;
  export)
    exec "$HL" "$PROJ_DIR" $PROJ -process $PROG -noanalysis -scriptPath "$PWD/tools/ghidra" \
      -postScript ExportFunctions.java "$PWD/config" "$PWD/out" -log "$PWD/out/ghidra-export.log" ;;
  script)
    shift; S=$1; shift
    exec "$HL" "$PROJ_DIR" $PROJ -process $PROG -noanalysis -scriptPath "$PWD/tools/ghidra" -postScript "$S.java" "$@" -log "$PWD/out/ghidra-$S.log" ;;
  *) sed -n '2,6p' "$0"; exit 2 ;;
esac
