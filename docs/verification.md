# Frame verification tools (task 002, 2026-10-05)

Every visual check compares a captured frame with a reference frame (a PPSSPP capture in `ref/` or an earlier run)
with a tolerance. The tools are pure Python 3.13 with zlib only (no PIL, no numpy, no venv), so they run in every
worktree and subagent as they are.

## tools/png.py

| Function | Does |
|---|---|
| `read_png(path)` | returns `(width, height, channels, bytes)`, rows top first, channels interleaved (1 grey, 2 grey+alpha, 3 RGB, 4 RGBA). 8-bit non-interlaced only, filter types 0-4, chunk CRCs checked. Anything else (palette, 1/2/4/16-bit, Adam7) raises `ValueError` naming the IHDR fields. |
| `write_png(path, width, height, channels, bytes)` | writes the same layout back, filter type 0 on every row. |
| `read_bmp(path)` | reads the framework's `PURE_SCREENSHOT_DIR` captures (24-bit, bottom-up, BGR) and 32-bit BMPs (BI_RGB, fourth byte dropped; BI_BITFIELDS with byte-aligned masks, alpha kept when the header has an alpha mask), bottom-up or top-down. Same return value as `read_png`. |

The BMP captures can be used directly; no `sips -s format png` step is needed. `read_bmp` on a capture gives the same
pixels as the sips-converted PNG beside it (checked on `out/shots/frame_{60,120,600,1260}`). A 960x544 capture with
Paeth-filtered rows reads in about 0.12 s, a BMP in a few milliseconds.

## tools/imgdiff.py

```
tools/imgdiff.py A B [--tol 24] [--max-frac 0.02] [--mask mask.png] [--region x,y,w,h] [--out diff.png] [--json]
tools/imgdiff.py A [B] --min-variance V [--region x,y,w,h] [--json]
tools/imgdiff.py --selftest
```

A and B are PNG or BMP, recognised by their magic bytes. Alpha is dropped and grey is spread to RGB before
anything is compared.

| Option | Meaning |
|---|---|
| (sizes differ) | both frames are resized to 480x272 by nearest neighbour (source pixel `floor(x * w / 480)`), so a 960x544 capture compares against a 480x272 PPSSPP reference. Frames of the same size are compared at their own size. |
| `--tol T` | a pixel differs when any channel differs by more than T (default 24). |
| `--max-frac F` | PASS (exit 0) when differing / total is at most F (default 0.02), FAIL (exit 1) otherwise. Bad input or unreadable files exit 2. |
| `--mask M` | pixels that are black in M (every channel below 128) are ignored and leave the total. M is resized to the comparison size. |
| `--region x,y,w,h` | in PSP screen pixels (480x272) whatever the frame size; scaled to the frame being measured (x2 on a 960x544 capture). Without `--min-variance` it limits the comparison to that rectangle (combined with `--mask` if both are given). |
| `--min-variance V` | no comparison: PASS when the largest per-channel variance of A inside the region (the whole frame without `--region`) is at least V. A "something is drawn here" check; B may be omitted. |
| `--out D` | writes a PNG at the comparison size: A dimmed to a third, differing pixels pure red. |
| `--json` | prints one JSON object instead of the text line. Compare mode: `result`, `mode`, `width`, `height`, `fraction`, `differing`, `total`, `tol`, `max_frac`, `resized`, `a_size`, `b_size`, `mask`, `region`, `pixel_region`, `out`. Variance mode: `result`, `mode`, `width`, `height`, `region`, `pixel_region`, `variance` (R, G, B), `max_variance`, `min_variance`. |

Examples:
```
tools/imgdiff.py out/shots/frame_900.bmp ref/frontend.png --out out/frontend-diff.png
tools/imgdiff.py out/shots/frame_600.bmp --region 140,100,200,40 --min-variance 100
```

## Self-test

`python3 tools/imgdiff.py --selftest` builds synthetic 480x272 images in a temporary directory and checks: identical
frames give 0.0; the top-left quadrant shifted 7 px gives 0.25 +/- 0.01 (FAIL) and the diff image marks exactly the
differing pixels red; a mask over that quadrant and a region on another quadrant give 0.0; a 960x544 BMP against the
480x272 PNG of the same picture gives 0.0; BMP round trips (24-bit with padded rows, 32-bit top-down, 32-bit V5
bitfields with alpha); PNG rows written with each of the filter types 0-4 at 1 to 4 channels; a 16-bit PNG is
rejected with its IHDR fields; the variance check fails on a flat region and passes on a drawn one; the CLI's
`--json` keys and exit code. It prints PASS and exits 0 in under 2 s (0.15 s on this Mac, about 0.7 s on a first run while Python compiles the modules).
