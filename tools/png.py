"""Dependency-free PNG and BMP pixel I/O (Python 3.13, zlib only).

  read_png(path)  -> (width, height, channels, bytes)
  write_png(path, width, height, channels, data)
  read_bmp(path)  -> (width, height, channels, bytes)

Pixels are 8 bits per channel, rows top first, channels interleaved: 1 = grey, 2 = grey+alpha, 3 = RGB,
4 = RGBA. read_png takes 8-bit non-interlaced greyscale, grey+alpha, RGB and RGBA with any of the filter types 0-4;
anything else (palette, 1/2/4/16-bit, Adam7) raises ValueError naming the IHDR fields. write_png writes filter 0
only. read_bmp takes the framework's 24-bit bottom-up captures and 32-bit BMPs (BI_RGB, whose fourth byte is
reserved and dropped, or BI_BITFIELDS with byte-aligned masks, which keeps alpha when an alpha mask is set),
bottom-up or top-down.
"""
import struct, zlib
from itertools import accumulate
from operator import add

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
_CHANNELS = {0: 1, 2: 3, 4: 2, 6: 4}      # PNG colour type -> channels (8-bit only)
_COLOUR_TYPE = {v: k for k, v in _CHANNELS.items()}
_MOD256 = bytes(range(256)) * 2           # _MOD256[s] == s & 255 for 0 <= s < 512
_LOW_BYTE = (255).__and__


def _unfilter(raw, width, height, bpp):
    """Reverses PNG filtering; raw holds height rows of one filter byte plus width * bpp bytes."""
    stride = width * bpp
    if len(raw) < height * (stride + 1):
        raise ValueError(f"PNG image data is {len(raw)} bytes, expected {height * (stride + 1)}")
    rows = []
    prev = bytes(stride)
    pos = 0
    for y in range(height):
        ftype = raw[pos]
        cur = raw[pos + 1:pos + 1 + stride]
        pos += stride + 1
        if ftype == 0:
            pass
        elif ftype == 1:      # Sub: running sum per channel
            out = bytearray(stride)
            for k in range(bpp):
                out[k::bpp] = bytes(map(_LOW_BYTE, accumulate(cur[k::bpp])))
            cur = bytes(out)
        elif ftype == 2:      # Up
            cur = bytes(map(_MOD256.__getitem__, map(add, cur, prev)))
        elif ftype == 3:      # Average
            out = bytearray(stride)
            for k in range(bpp):
                vals = []
                a = 0
                for x, b in zip(cur[k::bpp], prev[k::bpp]):
                    a = (x + ((a + b) >> 1)) & 255
                    vals.append(a)
                out[k::bpp] = bytes(vals)
            cur = bytes(out)
        elif ftype == 4:      # Paeth
            out = bytearray(stride)
            for k in range(bpp):
                vals = []
                a = c = 0
                for x, b in zip(cur[k::bpp], prev[k::bpp]):
                    pa = b - c if b >= c else c - b            # |p - a| with p = a + b - c
                    pb = a - c if a >= c else c - a            # |p - b|
                    pc = a + b - c - c
                    if pc < 0:
                        pc = -pc                                # |p - c|
                    if pa <= pb and pa <= pc:
                        a = (x + a) & 255
                    elif pb <= pc:
                        a = (x + b) & 255
                    else:
                        a = (x + c) & 255
                    vals.append(a)
                    c = b
                out[k::bpp] = bytes(vals)
            cur = bytes(out)
        else:
            raise ValueError(f"PNG row {y} has unknown filter type {ftype}")
        rows.append(cur)
        prev = cur
    return b"".join(rows)


def read_png(path):
    """Returns (width, height, channels, bytes) for an 8-bit non-interlaced grey, grey+alpha, RGB or RGBA PNG."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != PNG_SIGNATURE:
        raise ValueError(f"{path}: not a PNG file")
    pos, ihdr, idat = 8, None, []
    while pos + 8 <= len(data):
        length, ctype = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        crc = data[pos + 8 + length:pos + 12 + length]
        if len(body) != length or len(crc) != 4:
            raise ValueError(f"{path}: truncated {ctype!r} chunk")
        if struct.unpack(">I", crc)[0] != zlib.crc32(ctype + body):
            raise ValueError(f"{path}: CRC mismatch in {ctype!r} chunk")
        if ctype == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", body[:13])
        elif ctype == b"IDAT":
            idat.append(body)
        elif ctype == b"IEND":
            break
        pos += 12 + length
    if ihdr is None:
        raise ValueError(f"{path}: no IHDR chunk")
    width, height, depth, colour, compression, filtering, interlace = ihdr
    if depth != 8 or colour not in _CHANNELS or compression != 0 or filtering != 0 or interlace != 0:
        raise ValueError(f"{path}: unsupported PNG (IHDR width={width} height={height} bit_depth={depth} "
                         f"colour_type={colour} compression={compression} filter={filtering} "
                         f"interlace={interlace}); only 8-bit non-interlaced colour types 0, 2, 4, 6 are read")
    channels = _CHANNELS[colour]
    pixels = _unfilter(zlib.decompress(b"".join(idat)), width, height, channels)
    return width, height, channels, pixels


def _chunk(ctype, body):
    return struct.pack(">I", len(body)) + ctype + body + struct.pack(">I", zlib.crc32(ctype + body))


def write_png(path, width, height, channels, data):
    """Writes an 8-bit grey (1), grey+alpha (2), RGB (3) or RGBA (4) PNG with filter type 0 on every row."""
    if channels not in _COLOUR_TYPE:
        raise ValueError(f"write_png: channels must be 1, 2, 3 or 4, not {channels}")
    stride = width * channels
    if len(data) != stride * height:
        raise ValueError(f"write_png: {len(data)} bytes for {width}x{height}x{channels}")
    raw = b"".join(b"\x00" + data[y * stride:(y + 1) * stride] for y in range(height))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, _COLOUR_TYPE[channels], 0, 0, 0)
    with open(path, "wb") as f:
        f.write(PNG_SIGNATURE + _chunk(b"IHDR", ihdr) + _chunk(b"IDAT", zlib.compress(raw, 6))
                + _chunk(b"IEND", b""))


def _mask_byte(mask, path):
    """Byte offset within a little-endian 32-bit pixel for a byte-aligned channel mask."""
    for k in range(4):
        if mask == 0xFF << (8 * k):
            return k
    raise ValueError(f"{path}: BMP channel mask {mask:#010x} is not byte-aligned")


def read_bmp(path):
    """Returns (width, height, channels, bytes), rows top first, for a 24-bit or 32-bit uncompressed BMP."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:2] != b"BM" or len(data) < 54:
        raise ValueError(f"{path}: not a BMP file")
    offset = struct.unpack("<I", data[10:14])[0]
    header_size, width, height, planes, bpp, compression = struct.unpack("<IiiHHI", data[14:34])
    if header_size < 40:
        raise ValueError(f"{path}: BMP core header ({header_size} bytes) not supported")
    top_down = height < 0
    height = abs(height)
    if bpp == 24 and compression == 0:
        order, channels = (2, 1, 0), 3                                    # stored B, G, R
    elif bpp == 32 and compression == 0:
        order, channels = (2, 1, 0), 3                                    # B, G, R, reserved
    elif bpp == 32 and compression in (3, 6):                             # BI_BITFIELDS, BI_ALPHABITFIELDS
        masks = struct.unpack("<III", data[54:66])      # inside a V2+ header, or right after a 40-byte one
        alpha = 0
        if header_size >= 56 or compression == 6:
            alpha = struct.unpack("<I", data[66:70])[0]
        order = tuple(_mask_byte(m, path) for m in masks)
        channels = 3
        if alpha:
            order += (_mask_byte(alpha, path),)
            channels = 4
    else:
        raise ValueError(f"{path}: unsupported BMP (bits={bpp} compression={compression}); "
                         "only 24-bit and 32-bit uncompressed or bitfields are read")
    step = bpp // 8
    stride = (width * bpp + 31) // 32 * 4
    row_bytes = width * step
    if offset + stride * (height - 1) + row_bytes > len(data):
        raise ValueError(f"{path}: BMP pixel data is truncated")
    ys = range(height) if top_down else range(height - 1, -1, -1)
    src = b"".join(data[offset + y * stride:offset + y * stride + row_bytes] for y in ys)
    out = bytearray(width * height * channels)
    for k, byte in enumerate(order):
        out[k::channels] = src[byte::step]
    return width, height, channels, bytes(out)
