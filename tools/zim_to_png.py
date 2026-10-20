#!/usr/bin/env python3
"""Convert a ZIM image (an HD texture pack's file) to PNG, level 0 only.

  tools/zim_to_png.py FILE.zim OUT.png

A ZIM image is the 16-byte header `ZIMG`, width, height, flags (little-endian u32), then the pixels: a zstd frame
when flags has 4096 (ZSTD_COMPRESSED; every file of the Wipeout Pure HD pack, D-024), a zlib stream when it has 256,
raw otherwise. The low four bits of flags are the format: 0 RGBA8888 (bytes R, G, B, A), 1 RGBA4444 and 2 RGB565
(16-bit little-endian words, red in the high bits); with HAS_MIPS (16) smaller levels follow level 0 and are left
out. zstd is decoded by the `zstd` executable on PATH (Python 3.13 here has no zstd module); the PNG is written by
tools/png.py (zlib only). Prints the size and flags; exit 0 written, 1 a file that is not a ZIM image it reads, 2
bad arguments or no `zstd` on PATH for a zstd payload. The PNG is derived from the pack: it stays under out/.
"""
import os, shutil, struct, subprocess, sys, zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import png  # noqa: E402  (tools/png.py)

ZLIB, ZSTD, FORMAT_MASK = 256, 4096, 15


def rgba(data, width, height, fmt):
    """Level 0 as RGBA8 bytes."""
    count = width * height
    if fmt == 0:
        return data[:count * 4]
    out = bytearray(count * 4)
    for i, (word,) in enumerate(struct.iter_unpack("<H", data[:count * 2])):
        if fmt == 1:  # RGBA4444, red in the high nibble
            r, g, b, a = (word >> 12) & 15, (word >> 8) & 15, (word >> 4) & 15, word & 15
            out[i * 4:i * 4 + 4] = bytes((r * 17, g * 17, b * 17, a * 17))
        else:  # RGB565, red in the high bits
            r, g, b = (word >> 11) & 31, (word >> 5) & 63, word & 31
            out[i * 4:i * 4 + 4] = bytes(((r * 255 + 15) // 31, (g * 255 + 31) // 63, (b * 255 + 15) // 31, 255))
    return bytes(out)


def main(argv):
    if len(argv) != 3 or argv[1] in ("-h", "--help"):
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    source, target = argv[1], argv[2]
    try:
        with open(source, "rb") as f:
            blob = f.read()
    except OSError as error:
        print(f"zim_to_png: cannot read {source}: {error.strerror}", file=sys.stderr)
        return 1
    if len(blob) < 16 or blob[:4] != b"ZIMG":
        print(f"zim_to_png: {source} is not a ZIM image (no ZIMG header)", file=sys.stderr)
        return 1
    width, height, flags = struct.unpack_from("<III", blob, 4)
    fmt = flags & FORMAT_MASK
    if fmt > 2 or width == 0 or height == 0:
        print(f"zim_to_png: {source}: format {fmt}, {width}x{height}: not read", file=sys.stderr)
        return 1
    payload = blob[16:]
    if flags & ZSTD:
        zstd = shutil.which("zstd")
        if zstd is None:
            print("zim_to_png: the payload is zstd and there is no `zstd` on PATH (brew install zstd)", file=sys.stderr)
            return 2
        run = subprocess.run([zstd, "-d", "-c", "-q"], input=payload, capture_output=True)
        if run.returncode != 0:
            print(f"zim_to_png: zstd failed: {run.stderr.decode(errors='replace').strip()}", file=sys.stderr)
            return 1
        data = run.stdout
    elif flags & ZLIB:
        data = zlib.decompress(payload)
    else:
        data = payload
    need = width * height * (4 if fmt == 0 else 2)
    if len(data) < need:
        print(f"zim_to_png: {source}: {len(data)} bytes of pixels, level 0 needs {need}", file=sys.stderr)
        return 1
    png.write_png(target, width, height, 4, rgba(data, width, height, fmt))
    compression = "zstd" if flags & ZSTD else "zlib" if flags & ZLIB else "raw"
    print(f"zim_to_png: {source}: {width}x{height}, flags {flags} (format {fmt}, {compression}) -> {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
