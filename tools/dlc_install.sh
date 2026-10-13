#!/bin/bash
# Installs download packs on the game's memory stick (task 077, docs/dlc.md): every pack folder found in PACKS is
# checked and copied into <data dir>/ms0/PSP/SAVEDATA/, where the game finds it at its next start.
#   tools/dlc_install.sh [--data-dir DIR] [--replace] PACKS
#   PACKS       a pack folder (UCUS98612D<PACK>), or a folder holding them, or its SAVEDATA, or its PSP/SAVEDATA (the
#               first of the three that holds any; a memory stick's root works). Read only: nothing is written there.
#   --data-dir  the data directory whose stick gets the packs (a game directory too: a stick is <dir>/ms0); default
#               the app's, PURE_DATA_DIR when set, else ~/Library/Application Support/pure-recomp/PureNative on macOS
#               and %APPDATA%\pure-recomp\PureNative on Windows (docs/release.md). Made when missing.
#   --replace   a pack already on the stick is replaced by the copy; without it, it is skipped with a line.
# Each folder is checked first (tools/purelib/dlc.py): its name is one of the twelve US packs, it holds PI.WAD (either
# case) and PARAM.SFO, and PARAM.SFO's SAVEDATA_DIRECTORY is the folder's name. A European pack (UCES00001D...) is
# refused by name. The copy goes beside its destination first (.install-<name>) and is renamed into place, so a
# failed copy leaves the stick as it was. Nothing but the packs' own folders is created or replaced.
# Prints one line per folder (installed, replaced, skipped or refused, and why) and a summary. Exit 0 when nothing was
# refused, 1 when a folder was refused or could not be copied, 2 when PACKS is not a folder or holds no pack folder.
set -u
TOOLS=$(cd "$(dirname "$0")" && pwd)
DATA=
REPLACE=no
PACKS=
usage() {
  echo "usage: tools/dlc_install.sh [--data-dir DIR] [--replace] PACKS"
  exit 2
}
while [ $# -gt 0 ]; do
  case $1 in
    --data-dir) [ $# -ge 2 ] || usage; DATA=$2; shift 2 ;;
    --replace) REPLACE=yes; shift ;;
    -h|--help) usage ;;
    -*) echo "dlc_install: unknown argument $1"; usage ;;
    *) [ -z "$PACKS" ] || usage; PACKS=$1; shift ;;
  esac
done
[ -n "$PACKS" ] || usage
# A path as Python takes it: Git Bash's /c/... as C:/... on Windows.
native() { case "$(uname -s)" in MINGW*|MSYS*) [ -n "$1" ] && cygpath -m "$1" || echo "$1" ;; *) echo "$1" ;; esac; }

python3 - "$(native "$TOOLS")" "$(native "$PACKS")" "$(native "$DATA")" "$REPLACE" <<'EOF'
import os, shutil, sys
from pathlib import Path

tools, packs, data, replace = sys.argv[1], Path(sys.argv[2]), sys.argv[3], sys.argv[4] == "yes"
sys.path.insert(0, tools)
from purelib import dlc  # noqa: E402  (tools/purelib/dlc.py)

if not packs.is_dir():
    print(f"dlc_install: {packs} is not a folder")
    sys.exit(2)
data = Path(os.path.abspath(data)) if data else dlc.app_data_dir()
savedata = data / "ms0" / "PSP" / "SAVEDATA"
folders = dlc.find(packs)
if not folders:
    print(f"dlc_install: no pack folder ({dlc.PREFIX}<PACK>) in {packs}, its SAVEDATA or its PSP/SAVEDATA")
    sys.exit(2)
print(f"dlc_install: {len(folders)} pack folder(s) in {folders[0].parent} -> {savedata}")


def size(folder):
    total = sum(f.stat().st_size for f in folder.rglob("*") if f.is_file())
    return f"{total / 1e6:.1f} MB"


counts = {"installed": 0, "replaced": 0, "skipped": 0, "refused": 0}


def line(state, name, text):
    counts[state] += 1
    print(f"  {state:<9} {name:<22} {text}")


failed = False
for folder in folders:
    name = folder.name
    why = dlc.check(folder)
    if why:
        line("refused", name, why)
        continue
    target = savedata / name
    title = dlc.PACKS[name]
    if target.exists() and os.path.realpath(target) == os.path.realpath(folder):
        line("skipped", name, f"{title}: this is the installed folder itself")
        continue
    if target.exists() and not replace:
        line("skipped", name, f"{title}: already on the stick (--replace replaces it)")
        continue
    staging = savedata / f".install-{name}"
    aside = savedata / f".replaced-{name}"
    try:
        savedata.mkdir(parents=True, exist_ok=True)
        shutil.rmtree(staging, ignore_errors=True)     # a partial copy left by an earlier failed install
        shutil.copytree(folder, staging)
        existed = target.exists()
        if existed:
            shutil.rmtree(aside, ignore_errors=True)
            os.rename(target, aside)
        os.rename(staging, target)
        if existed:
            shutil.rmtree(aside)
    except OSError as e:
        shutil.rmtree(staging, ignore_errors=True)
        if aside.exists() and not target.exists():
            os.rename(aside, target)                  # put the pack it was replacing back
        print(f"  failed    {name:<22} {e}")
        failed = True
        continue
    line("replaced" if existed else "installed", name, f"{title}, {size(target)}")

on_stick = [n for n in dlc.PACKS if (savedata / n).is_dir()]
print(f"dlc_install: {counts['installed']} installed, {counts['replaced']} replaced, {counts['skipped']} skipped, "
      f"{counts['refused']} refused{', a copy failed' if failed else ''}; the stick holds {len(on_stick)} of the "
      f"twelve US packs")
sys.exit(1 if counts["refused"] or failed else 0)
EOF
