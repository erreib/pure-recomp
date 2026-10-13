"""The download packs (task 077, docs/dlc.md): the twelve US pack folders, the checks tools/dlc_install.sh makes on a
folder before it copies one, and where the app's data directory is. Reads a pack's PARAM.SFO and the names of its
files; never a byte of PI.WAD.
"""
import os
import struct
import sys
from pathlib import Path

PREFIX = "UCUS98612D"           # the frontend opens ms:\<folder>\PI.WAD for every folder whose name starts so
OTHER_RELEASE = "UCES00001D"    # the European set: the US game never opens it and could not read it (docs/dlc.md)
# The twelve US packs, as the profile lists them (src/profile/pure_profile.cpp, kSaveFolders): the folder and its
# PARAM.SFO's SAVEDATA_TITLE (Delta 1's "Delat" corrected).
PACKS = {
    "UCUS98612DCLASSICPACK1": "Classic Pack 1",
    "UCUS98612DCLASSICPACK2": "Classic Pack 2",
    "UCUS98612DCLASSICPACK3": "Classic Pack 3",
    "UCUS98612DDELTAPACK1": "Delta Pack 1",
    "UCUS98612DDELTAPACK2": "Delta Pack 2",
    "UCUS98612DGAMMAPACK1": "Gamma Pack 1",
    "UCUS98612DGAMMAPACK2": "Gamma Pack 2",
    "UCUS98612DGAMMAPACK3": "Gamma Pack 3",
    "UCUS98612DPAKDAXTER": "Daxter Pack",
    "UCUS98612DPAKJAKX": "Jak X Pack",
    "UCUS98612DPAKSOCOM3": "Socom 3 Pack",
    "UCUS98612DPAKSOCOMFTB": "Socom FTB Pack",
}
MAX_SFO = 64 * 1024             # a real PARAM.SFO is a few kilobytes (the framework's limit, save_transfer.cpp)


def param_sfo(path):
    """PARAM.SFO's entries as {key: str | int | bytes}; ValueError when it is not one."""
    with open(path, "rb") as f:
        data = f.read(MAX_SFO + 1)
    if len(data) > MAX_SFO or len(data) < 20 or data[:4] != b"\0PSF":
        raise ValueError("not a PARAM.SFO")
    _, keys, values, count = struct.unpack_from("<IIII", data, 4)
    entries = {}
    for i in range(count):
        if 20 + 16 * i + 16 > len(data):
            raise ValueError("PARAM.SFO is damaged")
        key_at, kind, length, _, value_at = struct.unpack_from("<HHIII", data, 20 + 16 * i)
        start = keys + key_at
        end = data.find(b"\0", start)
        value = data[values + value_at:values + value_at + length]
        if end < 0 or len(value) != length:
            raise ValueError("PARAM.SFO is damaged")
        key = data[start:end].decode("ascii", "replace")
        if kind == 0x0204:          # UTF-8, zero-terminated
            entries[key] = value.split(b"\0", 1)[0].decode("utf-8", "replace")
        elif kind == 0x0404 and length == 4:
            entries[key] = struct.unpack("<I", value)[0]
        else:
            entries[key] = value
    return entries


def find(picked):
    """The pack folders a player points at: `picked` itself when its name starts with PREFIX or OTHER_RELEASE, else
    the folders so named in the first of `picked`, `picked/SAVEDATA`, `picked/PSP/SAVEDATA` that holds any (as the
    menu's Import looks: save_transfer.cpp, find_saves). Sorted by name."""
    picked = Path(picked)
    if picked.name.startswith((PREFIX, OTHER_RELEASE)):
        return [picked]
    for base in (picked, picked / "SAVEDATA", picked / "PSP" / "SAVEDATA"):
        try:
            found = sorted(p for p in base.iterdir() if p.is_dir() and p.name.startswith((PREFIX, OTHER_RELEASE)))
        except OSError:
            continue
        if found:
            return found
    return []


def file_named(folder, name):
    """The file of `folder` named `name` in any case (the packs carry PI.WAD and pi.wad), or None."""
    try:
        for entry in Path(folder).iterdir():
            if entry.name.upper() == name.upper() and entry.is_file():
                return entry
    except OSError:
        pass
    return None


def check(folder):
    """Why the folder cannot be installed, or None: its name is one of the twelve, it holds PI.WAD (either case) and
    PARAM.SFO, and PARAM.SFO's SAVEDATA_DIRECTORY is the folder's name."""
    folder = Path(folder)
    name = folder.name
    if name.startswith(OTHER_RELEASE):
        return "a pack of the European release (UCES-00001): the US game neither opens nor reads it (docs/dlc.md)"
    if name not in PACKS:
        return f"{name} is not one of the twelve US packs"
    if file_named(folder, "PI.WAD") is None:
        return "no PI.WAD in it"
    sfo = file_named(folder, "PARAM.SFO")
    if sfo is None:
        return "no PARAM.SFO in it"
    try:
        directory = param_sfo(sfo).get("SAVEDATA_DIRECTORY")
    except (OSError, ValueError) as e:
        return f"PARAM.SFO cannot be read ({e})"
    if directory != name:
        return f"its PARAM.SFO names the folder {directory or '(nothing)'}"
    return None


def app_data_dir():
    """The app's data directory (docs/release.md): PURE_DATA_DIR when set, else SDL's preference folder for the
    profile's names: ~/Library/Application Support/pure-recomp/PureNative on macOS, %APPDATA%/pure-recomp/PureNative
    on Windows (elsewhere the XDG form, untried)."""
    if os.environ.get("PURE_DATA_DIR"):
        return Path(os.environ["PURE_DATA_DIR"])
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "pure-recomp" / "PureNative"
    if os.name == "nt":
        return Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming")) / "pure-recomp" / "PureNative"
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / "pure-recomp" / "PureNative"
