# pure-recomp

Static recompilation of Wipeout Pure (PSP, US Greatest Hits v2.00, UCUS-98612, ISO CRC32 4502C588) to a native
macOS arm64 build, on TeamGDB/PortableKit (MIT: the PSPRecomp framework plus its host layer), vendored at the
commit in `vendor/PIN` with the patches in `patches/`. Read `docs/vendor-map.md` and
`docs/status.md` first, then `docs/decisions.md`. The research behind every choice is in `docs/research.md`.

## Hard rules
- Never commit: `disc/`, `disc.iso`, `game/`, `generated/`, `vendor/`, `ref/*` captures, `build/`, `out/`, any bytes
  of the game, any DLC key. `config/` holds addresses, names, NIDs and hashes only.
- Never edit `vendor/` directly in a task unless the brief says so. If it does, export the change with
  `tools/patches.sh export NNNN-slug` and commit `patches/`, never `vendor/`.
- Never edit `vendor/portablekit/include/psprecomp/` (any change there recompiles the whole corpus, 8 to 20
  minutes). Never run `tools/regen.sh`. `tools/build.sh profile` is incremental (seconds when only `src/` changed).
  If your task needs the corpus regenerated or a full rebuild, stop and report BLOCKED.
- The compiler is `/usr/bin/clang` through `CMakePresets.json`. The `clang` first on PATH is an x86_64 clang 8
  from the Game Porting Toolkit and is wrong. `cmake`/`ninja` must be the arm64 ones from `/opt/homebrew`.
- No PPSSPP source code is copied into this repo. Reading PPSSPP code and docs to learn behaviour is fine.
- Work only on your branch (`task/NNN-slug`). Never touch `main`. Never push: the remote (`origin`, Erik's GitLab) is pushed by Erik alone.
- Game data: `disc/` (extracted from `disc.iso`, a symlink into `~/Downloads`) for tools, and `game/` (EBOOT.ELF,
  disc.iso, ms0/; made by `tools/setup_game.sh`) for the runtime. If `disc.iso` dangles, stop and say so; do not go
  looking for the image elsewhere.

## Build and run
```
tools/worktree_init.sh          # first thing in a fresh worktree: vendor clone, patches, disc link, gen cache
tools/build.sh profile          # incremental build of the host layer, our profile and the corpus in generated/
tools/run_boot.py [--seconds N] [--window] [--strict] [--env K=V] out/x.log   # bounded run, folded log
tools/verify_task.sh NNN        # runs the Verify line of docs/tasks/NNN-*.md and prints PASS or FAIL
```
Environment switches take the framework's names with our prefix: `PURE_NO_RENDER`, `PURE_NO_AUDIO` (headless),
`PURE_LIST_STUBS`, `PURE_STRICT_HLE`, `PURE_TRACE_KERNEL`, `PURE_TRACE_IO`, `PURE_TRACE_GE`, `PURE_TRACE_GE_LIST=N[:M]`,
`PURE_TRACE_SYNC`, `PURE_TRACE_MPEG`, `PURE_TRACE_ATRAC`, `PURE_TRACE_SAS`, `PURE_TRACE_AUDIO`, `PURE_TRACE_SAVEDATA`,
`PURE_TRACE_PAD`, `PURE_TRACE_PACING`, `PURE_GAME_DIR`, plus the framework-wide `PSPRECOMP_NO_INTERPRETER=1`,
`PSPRECOMP_MAX_DISPATCHES=N`, `PSPRECOMP_INTERPRETER_WATCH=addr,...`. Guest stdout/stderr appear as `[guest]` lines.
Switches this repo adds are listed in `README.md`.

## Task protocol (subagents)
1. Read `docs/tasks/NNN-slug.md` fully, then every file under "Read first".
2. Stay inside "May touch". If the fix needs a file under "Must not touch", stop: write the Result section with
   status BLOCKED and the reason, commit, and end.
3. Run the Verify command yourself before finishing; paste its last 20 lines into Result.
4. Append `## Result` to the task file: Status (DONE | PARTIAL | BLOCKED), Changed (files), Verify output (last
   20 lines), Open questions. Commit everything on your branch. Your final message is the Result section verbatim.
5. Escalate (BLOCKED) when: the escalation condition in the brief occurs; the vendor API differs from
   `docs/vendor-map.md`; a build exceeds 5 minutes; a halt or unsupported op appears outside your area; you would
   need to change the kernel scheduler, the code generator, or `include/psprecomp/`.
6. Prefer the smallest change that makes Verify pass. Do not refactor neighbouring code. Do not add dependencies.

## Commit style
Imperative subject of at most 72 characters, a body that says why, footer `Task: NNN`. One logical change per
commit. For vendor changes: `tools/patches.sh export NNNN-slug`, then add the row to `patches/README.md`.

## Conventions
C++20. Log lines carry a tag: `[guest]` game stdout, `[pure]` our profile, `[hle-stub]` unimplemented import,
`[io]` `[kernel]` `[mpeg]` `[render]` `[pacing]` framework traces. Tests live in `tests/` and are built by
`tools/build.sh profile`. Docs are plain prose with tables where they fit; no emojis. Dates are absolute.
