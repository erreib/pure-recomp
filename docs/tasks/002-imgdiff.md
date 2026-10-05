# 002: png.py and imgdiff.py, the frame comparison tools

Milestone: M2 | Branch: task/002-imgdiff | Status: OPEN

## Goal
Every visual check in this project compares a captured frame with a reference frame (PPSSPP or an earlier run) with a
tolerance. No PIL or numpy is installed; the tools must be pure Python 3.13 (zlib only), so they run in every
worktree and subagent without a venv.

## Read first
- CLAUDE.md
- docs/verification.md (create it if missing: one page describing the tools you write)
- ~/dev/pure-recomp/out/shots/frame_600.png and ~/dev/pure-recomp/out/shots/frame_1260.png (two captures of the same
  screen, for a self-test pair; read-only, absolute paths because your worktree has no out/)
- ref/README.md

## Deliverable
1. `tools/png.py`: `read_png(path) -> (width, height, channels, bytes)` and `write_png(path, width, height,
   channels, bytes)` for 8-bit greyscale, RGB and RGBA, PNG filter types 0-4 on read, filter 0 on write, zlib only.
   Also `read_bmp(path)` for the framework's 24/32-bit BMP captures so no `sips` step is needed.
2. `tools/imgdiff.py A B [--tol 24] [--max-frac 0.02] [--mask mask.png] [--region x,y,w,h] [--min-variance V]
   [--out diff.png] [--json]`: resizes both to 480x272 by nearest-neighbour when sizes differ (960x544 captures vs
   480x272 PPSSPP references), compares per channel, reports the fraction of pixels where any channel differs by
   more than `--tol`, PASS (exit 0) when the fraction is at most `--max-frac`, FAIL (exit 1) otherwise. `--mask`:
   pixels that are black in the mask are ignored. `--region` with `--min-variance`: instead of comparing, PASS when the
   region of A has per-channel variance at least V (a "something is drawn here" check; B may be omitted). `--out`
   writes a diff image (differing pixels in red over a dimmed A). `--json` prints the numbers as one JSON object.
3. `python3 tools/imgdiff.py --selftest`: builds synthetic images in a temp dir (identical -> 0.0; one quadrant
   shifted -> 0.25 +/- 0.01; a BMP round trip), runs them, prints PASS, exits 0. Runs in under 2 s on 480x272.

## Acceptance criteria
- [ ] `--selftest` passes.
- [ ] `python3 tools/imgdiff.py ~/dev/pure-recomp/out/shots/frame_600.png ~/dev/pure-recomp/out/shots/frame_1260.png --max-frac 0.02 --tol 24` passes
      (same screen, two captures); `--json` output includes width, height, fraction, differing, total.
- [ ] `read_bmp` on a `~/dev/pure-recomp/out/shots/*.bmp` capture gives the same pixels as the sips-converted PNG beside it
      (fraction 0.0 in imgdiff).

## Verify
`python3 tools/imgdiff.py --selftest && python3 tools/imgdiff.py out/shots/frame_600.png out/shots/frame_1260.png --max-frac 0.02 --tol 24`

## May touch
- tools/png.py, tools/imgdiff.py, docs/verification.md

## Must not touch
- everything else

## Estimated turns
20

## Escalate when
A capture in out/shots uses a PNG feature outside 8-bit non-interlaced (then report the IHDR fields and stop).

## Result
Status: DONE

Changed:
- `tools/png.py` (new): `read_png` (8-bit non-interlaced grey, grey+alpha, RGB, RGBA; filter types 0-4; chunk CRCs
  checked; anything else raises `ValueError` naming the IHDR fields), `write_png` (filter 0), `read_bmp` (24-bit
  bottom-up like the framework's `write_bmp`, 32-bit BI_RGB, 32-bit BI_BITFIELDS with byte-aligned masks).
- `tools/imgdiff.py` (new, executable): compare / mask / region / min-variance / out / json / selftest as briefed.
  Exit 0 PASS, 1 FAIL, 2 bad input.
- `docs/verification.md` (new): one page on both tools and the self-test.

Acceptance:
- `--selftest` passes (17 checks, 0.15 s warm, about 0.7 s cold): identical 0.0; top-left quadrant shifted 7 px
  0.2485, FAIL; BMP round trips (24-bit padded rows, 32-bit top-down, 32-bit V5 bitfields with alpha); plus diff
  image, mask, region, 960x544 BMP vs 480x272 PNG resize, PNG filters 0-4 at 1-4 channels, 16-bit rejection,
  variance pass/fail, CLI `--json` keys and exit code.
- frame_600.png vs frame_1260.png: PASS, fraction 0.0; `--json` has width, height, fraction, differing, total.
- `read_bmp` vs the sips-converted PNG: fraction 0.0 at `--tol 0 --max-frac 0` for frames 60, 120, 600 and 1260
  (byte-identical pixel buffers).
- Escalation check: all 21 PNGs in out/shots are IHDR 960x544, bit depth 8, colour type 2, interlace 0 (chunks IHDR,
  sRGB, eXIf, IDAT, IEND; rows use filters 0, 1, 2, 4). The BMPs are 24-bit, 40-byte header, bottom-up. No
  unsupported feature.

Verify output (last 20 lines). The worktree has no out/, so the Verify line was run with cwd ~/dev/pure-recomp and the
worktree's script by absolute path:
`cd ~/dev/pure-recomp && python3 $WT/tools/imgdiff.py --selftest && python3 $WT/tools/imgdiff.py out/shots/frame_600.png out/shots/frame_1260.png --max-frac 0.02 --tol 24`
```
  ok   png write/read round trip
  ok   identical frames: fraction 0.0
  ok   one quadrant shifted: fraction 0.2485
  ok   diff image marks differing pixels red: 32449 red, 32449 differing
  ok   mask hides the shifted quadrant
  ok   region on an untouched quadrant
  ok   960x544 BMP against 480x272 PNG
  ok   bmp round trip 24-bit bottom-up, padded rows
  ok   bmp round trip 32-bit top-down
  ok   bmp round trip 32-bit bitfields with alpha
  ok   bmp against png of the same pixels
  ok   png filter types 0-4, 1 to 4 channels
  ok   16-bit png rejected with IHDR fields
  ok   variance on a flat region fails: max 0.0
  ok   variance on a drawn region passes: max 5523.8
  ok   cli --json and exit code
  ok   under 2 s: 0.15 s
PASS selftest (0.15 s)
PASS fraction 0.000000 (0/522240 pixels differ by more than 24, limit 0.02) at 960x544
exit=0
```

Open questions:
- The Verify line uses relative `out/shots/...`, which does not exist in a worktree; `tools/verify_task.sh` (not in
  this tree yet) will need to run it from the main checkout or link `out/`.
- frame_600 and frame_1260 are byte-identical captures (the BMPs `cmp` equal), so this pair only proves the identical
  case; tolerance behaviour is covered by the self-test.
- Choices the brief left open, easy to flip: `--region` is in 480x272 PSP screen pixels and scaled to the frame
  (x2 on a 960x544 capture), so one region works for captures and PPSSPP references alike; `--region` without
  `--min-variance` limits the comparison to the rectangle; the variance check passes on the largest of the three
  per-channel variances (a red-only element counts as drawn; use the smallest if every channel must vary); a mask
  pixel counts as black when every channel is below 128, not only exactly 0; nearest neighbour samples
  `floor(x * w / 480)`, so a 960x544 capture keeps its even pixels.

## Review
(Fable fills)
