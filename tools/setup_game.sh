#!/bin/bash
# Lay out game/ the way the framework's developer build expects: EBOOT.ELF (the plain BOOT.BIN), disc.iso, ms0/.
set -e
cd "$(dirname "$0")/.."
[ -f disc/PSP_GAME/SYSDIR/BOOT.BIN ] || { echo "extract the disc first: python3 tools/iso_extract.py disc.iso extract disc"; exit 1; }
mkdir -p game/ms0/PSP/SAVEDATA
cp -f disc/PSP_GAME/SYSDIR/BOOT.BIN game/EBOOT.ELF
ln -sfn "$(readlink disc.iso)" game/disc.iso
echo "game/: $(ls game)"; shasum -a 256 game/EBOOT.ELF | cut -c1-16
