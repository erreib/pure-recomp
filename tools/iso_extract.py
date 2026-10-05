#!/usr/bin/env python3
"""Read a PSP UMD image (plain ISO9660) without mounting it.

Usage:
  tools/iso_extract.py <iso> list                 print size and path of every file
  tools/iso_extract.py <iso> extract <dir>        write every file under <dir> with its original path, plus MANIFEST.txt
  tools/iso_extract.py <iso> cat <path>           write one file's bytes to stdout (path like /PSP_GAME/PARAM.SFO)
  tools/iso_extract.py <iso> verify [<dir>]       check the image CRC32 against the known dump and, with <dir>, MANIFEST.txt

The only image this project accepts is Wipeout Pure (USA) v2.00, CRC32 4502C588. Anything else is refused by `verify`.
"""
import os, struct, sys, zlib

KNOWN = {0x4502C588: "Wipeout Pure (USA) (En,Fr,Es) (v2.00), UCUS-98612"}
SECTOR = 2048

class Iso:
    def __init__(self, path):
        self.f = open(path, "rb")
        pvd = self.sector(16)
        if pvd[1:6] != b"CD001":
            sys.exit(f"not an ISO9660 image: {path}")
        self.volume = pvd[40:72].decode("ascii", "replace").strip()
        _, ext, size, _, _ = self.record(pvd[156:190], 0)
        self.files = {}
        self.walk(ext, size, "/")

    def sector(self, n, count=1):
        self.f.seek(n * SECTOR)
        return self.f.read(SECTOR * count)

    @staticmethod
    def record(d, i):
        length = d[i]
        ext = struct.unpack_from("<I", d, i + 2)[0]
        size = struct.unpack_from("<I", d, i + 10)[0]
        flags = d[i + 25]
        nl = d[i + 32]
        return length, ext, size, flags, d[i + 33:i + 33 + nl]

    def walk(self, ext, size, path):
        d = self.sector(ext, (size + SECTOR - 1) // SECTOR)
        i = 0
        while i < len(d):
            if d[i] == 0:                      # padding to the next sector
                i = (i // SECTOR + 1) * SECTOR
                continue
            length, e, s, flags, name = self.record(d, i)
            i += length
            if name in (b"\x00", b"\x01"):     # . and ..
                continue
            n = name.decode("ascii", "replace").split(";")[0]
            if flags & 2:
                self.walk(e, s, path + n + "/")
            else:
                self.files[path + n] = (e, s)

    def read(self, path):
        ext, size = self.files[path]
        self.f.seek(ext * SECTOR)
        return self.f.read(size)

    def image_crc(self):
        self.f.seek(0)
        c = 0
        while True:
            b = self.f.read(1 << 24)
            if not b:
                break
            c = zlib.crc32(b, c)
        return c & 0xFFFFFFFF


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    iso, cmd = Iso(sys.argv[1]), sys.argv[2]
    if cmd == "list":
        total = 0
        for p in sorted(iso.files):
            s = iso.files[p][1]
            total += s
            print(f"{s:11d}  {p}")
        print(f"# volume {iso.volume!r}, {len(iso.files)} files, {total/1e6:.1f} MB")
    elif cmd == "cat":
        sys.stdout.buffer.write(iso.read(sys.argv[3]))
    elif cmd == "extract":
        out = sys.argv[3]
        lines = []
        for p in sorted(iso.files):
            data = iso.read(p)
            dest = os.path.join(out, p.lstrip("/"))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as w:
                w.write(data)
            lines.append(f"{len(data):11d}  {zlib.crc32(data) & 0xFFFFFFFF:08X}  {p}")
        with open(os.path.join(out, "MANIFEST.txt"), "w") as m:
            m.write("\n".join(lines) + "\n")
        print(f"extracted {len(lines)} files to {out}")
    elif cmd == "verify":
        crc = iso.image_crc()
        if crc not in KNOWN:
            sys.exit(f"REFUSED: image CRC32 {crc:08X} is not a known Wipeout Pure dump")
        print(f"image CRC32 {crc:08X}: {KNOWN[crc]}")
        if len(sys.argv) > 3:
            man = os.path.join(sys.argv[3], "MANIFEST.txt")
            bad = 0
            for line in open(man):
                size, c, p = line.split(None, 2)
                data = iso.read(p.strip())
                if len(data) != int(size) or f"{zlib.crc32(data) & 0xFFFFFFFF:08X}" != c:
                    print("MISMATCH", p.strip()); bad += 1
            if bad:
                sys.exit(f"{bad} files differ from MANIFEST.txt")
            print(f"MANIFEST.txt matches ({sum(1 for _ in open(man))} files)")
    else:
        sys.exit(__doc__)

if __name__ == "__main__":
    main()
