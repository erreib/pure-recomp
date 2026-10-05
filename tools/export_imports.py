#!/usr/bin/env python3
"""Write config/imports.csv from the game's ELF: every imported library function with its NID, name, and stub address.

Usage: tools/export_imports.py [disc/PSP_GAME/SYSDIR/BOOT.BIN] [--nids DIR]
Names come from psplibdoc-style XML files found under --nids (default: ~/dev/scratch/psp-ghidra-scripts and
~/dev/scratch/psplibdoc). Unknown NIDs get the name '?'. Addresses are module-relative; the runtime address of the
main module is relative + 0x08804000.
"""
import csv, glob, os, struct, sys
import xml.etree.ElementTree as ET

LOAD_BASE = 0x08804000

def load_nids(dirs):
    names = {}
    for d in dirs:
        for x in glob.glob(os.path.join(os.path.expanduser(d), "**", "*.xml"), recursive=True):
            try:
                root = ET.parse(x).getroot()
            except ET.ParseError:
                continue
            for lib in root.iter("LIBRARY"):
                ln = lib.findtext("NAME")
                for fn in lib.iter("FUNCTION"):
                    nid, nm = fn.findtext("NID"), fn.findtext("NAME")
                    if nid and nm:
                        names.setdefault((ln, int(nid, 16)), nm)
    return names

def sections(elf):
    shoff = struct.unpack_from("<I", elf, 32)[0]
    shnum, shstrndx = struct.unpack_from("<HH", elf, 48)
    sho, ssz = struct.unpack_from("<II", elf, shoff + shstrndx * 40 + 16)
    strs = elf[sho:sho + ssz]
    out = {}
    for i in range(shnum):
        nm, ty, fl, ad, of, sz = struct.unpack_from("<6I", elf, shoff + i * 40)
        out[strs[nm:strs.find(b"\0", nm)].decode()] = (ad, of, sz, ty)
    return out

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    path = args[0] if args else "disc/PSP_GAME/SYSDIR/BOOT.BIN"
    nid_dirs = [sys.argv[sys.argv.index("--nids") + 1]] if "--nids" in sys.argv else \
               ["~/dev/scratch/psp-ghidra-scripts", "~/dev/scratch/psplibdoc"]
    elf = open(path, "rb").read()
    secs = sections(elf)
    def rd(addr, n):
        for k, (ad, of, sz, ty) in secs.items():
            if ty != 8 and ad <= addr < ad + sz:
                return elf[of + addr - ad: of + addr - ad + n]
        return b""
    names = load_nids(nid_dirs)
    ad, of, sz, _ = secs[".lib.stub"]
    rows = []
    for i in range(sz // 20):
        nameptr, flags, counts, nidtab, stubtab = struct.unpack_from("<5I", elf, of + i * 20)
        nfunc = (counts >> 16) & 0xFFFF
        lib = rd(nameptr, 64); lib = lib[:lib.find(b"\0")].decode("ascii", "replace")
        for j in range(nfunc):
            nid = struct.unpack_from("<I", rd(nidtab + 4 * j, 4))[0]
            stub = stubtab + 8 * j
            rows.append((lib, f"0x{nid:08X}", names.get((lib, nid), "?"), f"0x{stub:06X}", f"0x{LOAD_BASE + stub:08X}"))
    rows.sort()
    with open("config/imports.csv", "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n"); w.writerow(["library", "nid", "name", "stub_rel", "stub_abs"]); w.writerows(rows)
    unknown = sum(1 for r in rows if r[2] == "?")
    print(f"{len(rows)} imports, {len(set(r[0] for r in rows))} libraries, {unknown} unresolved names -> config/imports.csv")
    if unknown:
        for r in rows:
            if r[2] == "?": print("  unresolved", r[0], r[1])

if __name__ == "__main__":
    main()
