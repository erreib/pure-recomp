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
(worker fills)

## Review
(Fable fills)
