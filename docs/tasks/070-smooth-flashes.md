# 070: A steady frame rate through the full-screen flashes (E6)

Milestone: E6 (Erik, 2026-10-11; D-016) | Branch: task/070-smooth-flashes | Status: MERGED (68803cd, 2026-10-11)

## Goal
Every race drops to 30 fps for 0.4 to 1.9 s at a time: at the race-start fade, when a weapon goes off near the
camera (a bomb, a mine, a missile), when the ship is put back on the track. That is the game's own rule, not the
port's (docs/fidelity.md "The two-vblank stretches: the game's own rule"; docs/timing.md step 5): the full-screen
flash object FxScreen (`FUN_0882da04`) stores 2 to the frame object's countdown at `+0x117c` on every frame its
effect runs, and the end-of-frame routine `FUN_0886511c` waits two vblanks a frame while that countdown is not 0 or
the mode's lock byte at `+0x116c` is 0. The game's simulation integrates a measured dt (`FUN_08804390`, from
`sceKernelGetSystemTimeWide`, capped at 0.067 s), so the wait does not set the race's speed. After this task the
port clears that countdown each frame in the free-running modes (`+0x116c` is 1: Single Race, Tournament), behind an
Esc-menu row that is on by default, and the checks run with it off so every measured scene stays where it was.

## Read first
- CLAUDE.md, docs/decisions.md (D-014, D-015, D-016: the decision this task carries out), docs/timing.md (step 5,
  "The two lock fields", "The game's clock in a race"), docs/fidelity.md ("The two-vblank stretches"),
  docs/history/fidelity.md ("What writes the two fields": the frame object is the one `DAT_08a8e960` points to;
  every writer of the two fields), README.md (the switches tables: `PURE_INTERNAL_SCALE`, `PURE_PACED_FROM`,
  `PURE_TRACE_CALLS`, `PURE_WATCH_SHIP`)
- src/profile/pure_profile.cpp (`wrap_flip_counter`: the pattern for wrapping a bound HLE call; `register_pure_hle`:
  the order things are bound in), src/profile/test_hooks.cpp (`wrap_call_traces`, `find_player_ship`: reading guest
  memory from a hook; `load32`, `load8`, `store32` on `rt.memory()`)
- patches/README.md, patches/0016-menu-rows-by-capability.patch and patches/0017-internal-scale-by-backend.patch
  (how a game-facing menu row and its setting were added), docs/upstream.md, `tools/patches.sh` (export, check)
- vendor/portablekit/host/profile.hpp (`GameProfile`, `MenuFeatures`), host/settings/settings.hpp and settings.cpp
  (the `Settings` struct, the key table around `video.internal_scale`: parse, save, the `<prefix>_<NAME>` variable,
  `overridden_by`, `defaults_for`), host/ui/menu.cpp (`Menu::video`, `section`, `choice_row`, `options_for`,
  `cycle`, the `<prefix>_MENU_DUMP` lines), host/hle/hle_media.cpp (the `sceGeDrawSync` handler)
- tools/menu_check.sh (the expected rows per tab), tools/purelib/port.py (`clean_env`, `steady_clock`,
  `SCRATCH_SETTINGS`; every tool runs the game through it), tools/run_boot.py (the internal-scale pin and `--env`),
  tools/frame_regress.sh (the race_hud row: `main_menu.txt+single_race.txt`, flip 6016), tools/fidelity_audit.py
  (`scan_log`, `STRETCH_MIN`, `TWO_VBLANK_US`, `stretch_of`: the two-vblank stretch rule; `run_cell`),
  tools/campaign_sweep.py (its usage: a Single Race cell, `--no-damage`, the follower fires pickups), tools/hud_check.py,
  docs/verification.md ("Which path for which change"), docs/controls.md ("Rebinding", "In settings.ini": where the
  menu's rows are documented)

## Deliverable
Two commits on the branch, in this order.

**1. The framework patch `patches/0019-game-option-rows.patch`** (generic: nothing in it names this game).
- `host/profile.hpp`: a `GameOption` (`key` as in settings.ini without the `game.` prefix, lower snake case; `label`,
  the row's text; `choices`, a span of texts, the row cycles through them; `description`, the help text; `default`,
  an index into choices; `tab`, which of the menu's tabs shows it) and `std::span<const GameOption> options` on
  `GameProfile` (empty by default).
- `host/settings/`: each option's value kept as an index (`std::uint32_t`), read and written in settings.ini as
  `game.<key>=<index>` (an index out of range, or a key the game has no option for, reads as the default and is
  dropped on save), the default from the option, a run-time variable `<prefix>_<KEY>` (the key upper-cased:
  `PURE_SMOOTH_FLASHES`) that overrides it for the run as `<prefix>_INTERNAL_SCALE` does `video.internal_scale`
  (`overridden_by("game.<key>")` names it, so the menu row shows "Set by ..." and is disabled), and an accessor
  `settings::game_option(const char *key)` returning the current index (the default for an unknown key). Reading
  the accessor each frame must be cheap (a lookup by key in a small table is fine).
- `host/ui/menu.cpp`: at the end of each tab that has options, a `section("Game")` with one `choice_row` per
  option (`options_for("game.<key>", description)`), saving on change. The dump lines list the rows as the others
  are listed. No option, no section.
- Exported with `tools/patches.sh export 0019-game-option-rows`; `tools/patches.sh check` says 19 patches reproduce
  the vendor; patches/README.md gets its row; docs/upstream.md its candidate line.

**2. The option, the hook, the pin, the check, the docs** (commit two).
- `src/profile/pure_profile.cpp` (or a new `src/profile/enhancements.cpp` declared in a header and listed in the
  build, if the profile file would grow past its purpose; the test hooks file is for test switches, not for this):
  the option table for this game, one entry: key `smooth_flashes`, label `Flashes`, choices `Original`, `Smooth`,
  default `Smooth` (index 1), tab Video, description along the lines of "The PSP halves the frame rate while a
  full-screen flash plays: the race-start fade, a weapon going off near you, your ship put back on the track.
  Smooth keeps the race's frame rate through them. The game's speed is the same either way (it measures time).
  Time Trial, Free Play and Zone run at 30 fps on the PSP and still do."
- The hook: wrap the bound `sceGe_user` `sceGeDrawSync` (NID 0xB287BD61; `hle.bound_function` then `hle.bind`, as
  `wrap_flip_counter` does for the flip) so that, when `settings::game_option("smooth_flashes")` is 1, before the
  original runs: read the frame object pointer at `0x08A8E960`; if it points into user RAM (0x08800000 to
  0x0A000000) and `load8(obj + 0x116c) == 1`, `store32(obj + 0x117c, 0)`. Nothing else: when the byte is 0 (the
  30-fps modes, the frontend) the field is left alone. Log once, at the first clear, `[pure] smooth flashes: on
  (game.smooth_flashes)`, and once if the option is off at start `[pure] smooth flashes: off`.
- Confirm the readers of `+0x117c`: the fidelity audit listed its writers; list every load of the field in
  `generated/` (the offset 4476 on the frame object, as the audit found the stores) and name them in the Result.
  If any reader other than `FUN_0886511c` acts on it, say what it does; if it would change behaviour, BLOCKED.
- The pin: `tools/purelib/port.py` gets `original_pacing(env)` (or a name of your choice in the same style as
  `steady_clock`): `env.setdefault("PURE_SMOOTH_FLASHES", "0")`, called wherever `steady_clock` or `silence` is
  called so that every tool's run (run_boot, campaign_sweep, fidelity_audit, scorecard, the shell scripts that go
  through run_boot) has it unless the caller sets the variable. `tools/run_boot.py --env PURE_SMOOTH_FLASHES=1`
  must win over the pin (read `--env` first, as the internal-scale pin does). Also add `game.smooth_flashes=0` to
  `SCRATCH_SETTINGS` so a scratch data directory's settings.ini says the same.
- `tools/flash_check.sh [--race] [--shell S] [--backend B]`, in the shape of `tools/billboard_check.sh`:
  - default: the race-start fade. Two headless runs of `main_menu.txt+single_race.txt` to flip 6100 with
    `PURE_TRACE_CALLS=sceDisplay:0x289D82FE` (a `[call]` line per flip with `t=`) and `PURE_WATCH_SHIP=1`, one with
    `--env PURE_SMOOTH_FLASHES=0` and one with `1`. For each, count the flips between 5600 and 6100 whose `t` is
    more than `TWO_VBLANK_US` (fidelity_audit's constant; about 25 ms) after the previous flip's, and the longest
    run of them. PASS when the run with 0 has a run of at least 50 such flips (the 57-flip fade; the fade's
    start may move by a few flips) and the run with 1 has at most 2 in all between the fade's start and 6100, and
    both runs print a `[pure] ship frame` line with `clock=` above 0 by flip 6100 (the race runs). Dump a frame at
    6100 in the run with 1 and pass it through `tools/hud_check.py` (the HUD is drawn). Print the counts, the
    longest runs and the wall time of the fade in both runs (with the option on, the fade should take about the
    same seconds and about twice the flips).
  - `--race`: two Single Race cells of Vineta K through `tools/campaign_sweep.py single_race vineta_k --no-damage`
    (headless, the sweep's defaults), one with `PURE_SMOOTH_FLASHES=0` in the environment and one with `1`,
    their logs scanned with fidelity_audit's rule (import `scan_log` from tools/fidelity_audit.py, as it imports
    campaign_sweep; do not copy the rule): PASS when the run with 1 has 0 stretches, and the mean lap time of the
    run with 1 is within 5% of the run with 0 (the race's speed unchanged; the follower drives the same table).
    Print both runs' stretches and lap times. Record the two runs' figures in the task's Result.
  - exit 0 on PASS; `flash_check: PASS ...`/`FAIL ...` as the last line.
- `tools/menu_check.sh`: the expected Video rows of both shells gain `Flashes` where the row appears (the menu's
  dump order); the check passes on both shells.
- Docs: README.md (the switches table: `PURE_SMOOTH_FLASHES=0|1`, the tools table: `tools/flash_check.sh`),
  docs/timing.md (a short section "E6: the flash lock cleared (task 070)" pointing at D-016 and the hook),
  docs/fidelity.md (the two-vblank section's last sentence: the enhancement exists, task 070, off in the checks),
  docs/controls.md (the Flashes row and `game.smooth_flashes` where the Video rows are described),
  docs/verification.md (the pin: every tool run has the option off; `tools/flash_check.sh` is the check that has
  it on), docs/release.md (settings.ini: `game.smooth_flashes`, default 1), patches/README.md and docs/upstream.md
  (commit one). `python3 tools/docs_check.py` passes.

## Acceptance criteria
- [ ] `tools/patches.sh check` reports 19 patches reproducing vendor/portablekit at 8b0c3fe; the patch names no
      game, no key, no label of this game
- [ ] `tools/flash_check.sh` PASS: the fade's two-vblank flips at least 50 with the option off, at most 2 with it on,
      the race runs and the HUD is drawn in both
- [ ] `tools/flash_check.sh --race` PASS: 0 stretches with the option on, lap times within 5% of the run with it off
- [ ] `tools/menu_check.sh` and `tools/menu_check.sh --shell vulkan` PASS with the Flashes row expected
- [ ] `tools/frame_regress.sh` PASS 18/18 (headless, the pin on) and `tools/hud_check.sh` 61 of 61: unchanged
- [ ] a 2200-flip frontend run (`tools/run_boot.py --frames 2200 --pad config/pad_scripts/main_menu.txt`) prints
      `[pure] smooth flashes: off` and no `smooth flashes: on` line; the same with `--env PURE_SMOOTH_FLASHES=1`
      prints `on` only once a race starts (the frontend's byte is 0), which `flash_check.sh` shows
- [ ] every reader of `+0x117c` in `generated/` named in the Result
- [ ] `python3 tools/docs_check.py` passes

## Verify
`tools/patches.sh check && tools/flash_check.sh && tools/flash_check.sh --race && tools/menu_check.sh && tools/menu_check.sh --shell vulkan && tools/frame_regress.sh && python3 tools/docs_check.py`

## May touch
- patches/0019-game-option-rows.patch (new, through `tools/patches.sh export`), patches/README.md, docs/upstream.md
- vendor/portablekit/host/profile.hpp, host/settings/settings.hpp, host/settings/settings.cpp, host/ui/menu.cpp
  (only through the patch; `tools/patches.sh check` must pass)
- src/profile/pure_profile.cpp, src/profile/pure_profile.hpp if present, a new src/profile/enhancements.{cpp,hpp}
  and the CMake list that builds src/profile
- tools/flash_check.sh (new), tools/menu_check.sh, tools/purelib/port.py, tools/run_boot.py
- README.md, docs/timing.md, docs/fidelity.md, docs/controls.md, docs/verification.md, docs/release.md,
  docs/tasks/070-smooth-flashes.md (the Result)

## Must not touch
- include/psprecomp/, generated/, config/, src/gpu/, src/host/, src/profile/test_hooks.*, the other patches,
  tools/fidelity_audit.py, tools/campaign_sweep.py, tools/frame_regress.sh, tools/hud_check.sh, ref/, docs/decisions.md,
  docs/status.md, anything not listed above

## Estimated turns
60

## Escalate when
- `sceGeDrawSync` is not called once per frame before the pacing step (the trace shows otherwise), or clearing the
  field at that point does not take the free path (the fade keeps its two-vblank flips with the option on)
- a reader of `+0x117c` other than the end-of-frame routine acts on it
- the lap times with the option on are not within 5% of the run with it off (the game's speed moved: stop, report
  the figures, do not tune)
- the settings code has no place for a per-game key without reworking its table (report the shape you would need)
- a build takes over 5 minutes, or the change needs include/psprecomp/ or generated code

## Result
Status: DONE. Every acceptance criterion holds; no escalation condition occurred (details below).

Changed (branch task/070-smooth-flashes from batch/m2 fcf89c2):
- Commit 1 (a1afaac), the framework patch: `patches/0019-game-option-rows.patch` (generic: names no game, key or
  label of this one), `patches/README.md` (row and section), `docs/upstream.md` (dependency row, candidate section,
  the order). `host/profile.hpp`: `MenuTab` (Video, Audio, Controls, Network, System) and `GameOption` (`key`,
  `label`, `choices`, `description`, `default_choice`, `tab`; `default` is a C++ keyword, so the brief's `default` is
  `default_choice`), `GameProfile::options`. `host/settings/`: `Settings::game_options` (an index each),
  `defaults_for` gives each its default, `all_fields()` adds `game.<key>` per option after the bindings, with the
  variable `<KEY>` (so `PURE_SMOOTH_FLASHES`, `overridden_by("game.smooth_flashes")`), an index out of range ignored
  (`[settings] ignoring ...`, the default stays), `save()` drops a `game.` key no option has,
  `settings::game_option(key)`. `host/ui/menu.cpp`: `game_rows(tab)` at the end of each tab (a `section("Game")`, a
  `choice_row` per option through the dump's row object, saving on change), and `restore_game_rows(tab)` in each
  tab's Restore button (not in the brief; "Restore video defaults" says every setting on the page). Tried: 0019
  applies on the pin plus 0003, 0004, 0016 and 0017, not without 0017.
- Commit 2: `src/profile/enhancements.{hpp,cpp}` (new: the option table, Flashes, `smooth_flashes`, Original/Smooth,
  default 1, Video; the `sceGeDrawSync` wrap), `src/profile/pure_profile.cpp` (installs it after the flip counter and
  before the test hooks, so `PURE_TRACE_CALLS` can wrap it; `.options`), `CMakeLists.txt` (the source),
  `tools/purelib/port.py` (`original_pacing`, called by `silence` and `steady_clock` so the sweep, which this task
  may not touch, gets it; `SCRATCH_SETTINGS` adds `game.smooth_flashes=0`), `tools/run_boot.py` (the call after
  `--env` is merged, and its doc), `tools/flash_check.sh` (new), `tools/menu_check.sh` (Flashes last in Video, both
  shells), README.md, docs/timing.md ("E6"), docs/fidelity.md, docs/controls.md, docs/verification.md,
  docs/release.md, this Result.

The readers of `+0x117c` (`grep 4476 generated/*.cpp`, each hit read in place):
- `FUN_0886511c` (generated_unit_0024.cpp lines 8780 and 8787): `aot_load32(s0 + 4476)`, the one load, at
  0x08865248: emitted twice, inline as the delay slot of the beq at 0x08865244 and at its own label. The only reader.
  Its decrement's store at 0x0886525C (lines 8805, 8809, likewise twice).
- The other stores, as the audit found: `FUN_0882da04` (FxScreen, unit 0010 line 12060, 0x0882E198, the 2) and
  `RenderManager_cpp__088666c4` (unit 0024 line 14769, 0x08866BC0, the 0).
- `FUN_0889e5ac` (unit 0038 lines 13274 and 13278): `a1 = (0x8A5 << 16) + 4476` = 0x08A5117C, a constant address
  (a string of the network-error names handed to FUN_088DF8EC), not the frame object: not a reader.

Measured:
- `sceGeDrawSync` (traced with `PURE_TRACE_CALLS=sceDisplay:0x289D82FE,sceGe_user:0xB287BD61`): exactly one call
  before each flip from the race's first frame (flips 5707 to 6400: 694 of 694); the frontend makes 1 to 3 a flip
  (+0x116c 0 there, so the hook writes nothing). The frame object is `0x08B77020` in these runs.
- The fade (`tools/flash_check.sh`): with 0, 57 flips at two vblanks (5708 to 5764, 1.90 s); with 1, none from 5708
  to 6100. The race clock starts at flip 6253 with 0 and 6309 with 1, 10.04 s and 10.02 s from the fade's first
  flip: the same time in 56 more flips. With 1, `[pure] smooth flashes: on (game.smooth_flashes)` once, in the
  race's first frame (after flip 5700); with 0, `off` at start-up only. HUD at 6100 in both.
- The race (`--race`): with 0, PASS, 4 stretches (flip 9649: 16 flips 0.53 s; 10540: 18, 0.60 s; 10648: 22, 0.73 s;
  10833: 16, 0.53 s), laps 59.6, 64.1, 56.4 s (mean 60.03); with 1, PASS, 0 stretches, laps 62.9, 55.4, 58.2 s
  (mean 58.83): -2.0%.
- 2200-flip frontend (`run_boot.py --frames 2200 --shell headless --script config/pad_scripts/main_menu.txt`):
  `[pure] smooth flashes: off` and no `on`; with `--env PURE_SMOOTH_FLASHES=1`, no line at all (the frontend's byte
  is 0; the `on` comes with the race, as above).
- settings.ini, a windowed run of the binary without the pin (data directory holding `game.smooth_flashes=5` and
  `game.bogus=1`): `[settings] ignoring game.smooth_flashes=5`, the row read Smooth, Right made it Original, and the
  file then held `game.smooth_flashes=0` and no `game.bogus`. The row and its help text drawn in the Game section.
- `tools/hud_check.sh`: 61 of 61 (Metal window). `tools/frame_regress.sh`: 18/18 with task 069's headless fractions
  to the digit (race_hud 0.0148, zone_change 0.0369).

Verify output (each part run on its own, last lines):
```
$ tools/patches.sh check
ok: 19 patch(es) reproduce vendor/portablekit at 8b0c3fe
$ tools/flash_check.sh
PURE_SMOOTH_FLASHES=0: flips 5600-6100: 164 at two vblanks, longest run 107; 107 before the race's first one-vblank flip (5707); the fade: flips 5708-5764, 57 flips, 1.90 s; the race clock starts at flip 6253, 546 flips and 10.04 s from the fade's first
PURE_SMOOTH_FLASHES=1: flips 5600-6100: 107 at two vblanks, longest run 107; 107 before the race's first one-vblank flip (5707); from the fade's first flip (5708) to 6100: 0 at two vblanks; the fade's 1.90 s span flips 5708-5822, 115 flips; the race clock starts at flip 6309, 602 flips and 10.02 s from the fade's first; '[pure] smooth flashes: on (game.smooth_flashes)' after flip 5700
flash_check: PASS (fade 57 flips off, 0 on; the race and its HUD in both)
$ tools/flash_check.sh --race
PURE_SMOOTH_FLASHES=0: PASS, laps 59.6, 64.1, 56.4 s (mean 60.03 s), 4 two-vblank stretch(es) (3+ flips over 25000 us)
PURE_SMOOTH_FLASHES=1: PASS, laps 62.9, 55.4, 58.2 s (mean 58.83 s), 0 two-vblank stretch(es) (3+ flips over 25000 us)
flash_check: PASS (race: stretches 4 off, 0 on; mean lap -2.0% on against off)
$ tools/menu_check.sh
Video: ok (11)
menu_check: PASS
$ tools/menu_check.sh --shell vulkan
Video: ok (17)
menu_check: PASS
$ tools/frame_regress.sh
frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 21s)
$ python3 tools/docs_check.py
docs_check: 33 files, 0 findings: PASS
```

Open questions:
1. The brief asks for a race clock above 0 "by flip 6100", but the race clock starts at flip 6253 with the option
   off (6309 on; single_race.txt: "goes at ~6250"), so no run can show it by 6100. The fade check runs to flip 6400
   and asks for it by then; the counted flips stay 5600 to 6100 and the HUD shot stays at 6100.
2. Flips 5600 to 5706 (TEAM SELECTION and the race load) are 107 two-vblank flips in both runs, the longest run of
   the brief's window, so the check takes the fade as the first run after the race's first one-vblank flip (5707).
   The load's flips (5701 to 5706) keep two vblanks with the option on although +0x116c is 1 and the countdown 0, so
   their wait is not step 5's; not chased.
3. With the option on the fade cannot be seen in the flip times (its flips are one vblank like their neighbours):
   the check prints the flips run 0's fade seconds span in run 1 (115) and, measured, the race clock's start from
   the fade's first flip in both runs (the same seconds, 56 more flips).
4. In the frontend the countdown runs negative (the locked path decrements it every frame: -5572 at flip 5700); the
   game's own, untouched, and cleared at the race's first frame with the option on.
5. The acceptance's `--pad` is not a run_boot flag; the frontend runs used `--script ... --shell headless`.

## Review
Verify rerun (main checkout, after the merge and `git -C vendor/portablekit apply` of 0019, `tools/build.sh profile`;
out/070_gate.log): `verify 070: PASS`. Its parts: `ok: 19 patch(es) reproduce vendor/portablekit at 8b0c3fe`;
`flash_check: PASS (fade 57 flips off, 0 on; the race and its HUD in both)` (the fade flips 5708-5764, 1.90 s; the
race clock 10.04 s after the fade's first flip with 0, 10.02 s with 1); `flash_check: PASS (race: stretches 2 off, 0
on; mean lap -4.1% on against off)` (off: laps 72.9, 55.2, 62.7 s with a 31-flip put-back at 157 m of lap 1 and a
22-flip weapon flash in lap 3; on: 61.0, 58.9, 63.1 s, no stretch); `menu_check: PASS` on both shells;
`frame regression: PASS, 18/18 scenes pass, shell headless, backend metal (0m 21s)` with the measured fractions to
the digit (race_hud 0.0149, zone_change 0.0353); `docs_check: 33 files, 0 findings: PASS`. Then
`hud_check: 61 of 61 shots have the HUD`.
Spot-read: src/profile/enhancements.cpp (the wrap writes only when the frame object is in user RAM and `+0x116c` is
1; one line at the first clear; the option read each call through `settings::game_option`, one strcmp),
src/profile/pure_profile.cpp (installed after the flip counter, before the test hooks), the patch (generic:
`GameOption`/`MenuTab`/`GameProfile::options`; `Settings::game_options` by index; `all_fields()` adds `game.<key>`
with the variable `<KEY>`; an index out of range ignored with a line; stale `game.` keys dropped on save;
`game_rows` at the end of each tab and `restore_game_rows` on each Restore button, which skips a row a variable
sets), tools/purelib/port.py (`original_pacing` from `silence` and `steady_clock`; the scratch settings), run_boot
(`--env` wins), flash_check.sh (the audit's rule imported, not copied), menu_check.sh (Flashes last in Video). No
file outside May touch; docs/status.md untouched by the branch.
Merged: 68803cd (`--no-ff` into batch/m2, 2026-10-11); worktree removed.
Notes: (1) The Flashes row sits after "Restore video defaults" (the Game section ends the tab); fine for one row,
revisit the placement when E4/E5 add more. (2) The `--race` lap-time bound is coarse: the two cells are different
races (the AI's weapons and a put-back differ run to run; this gate's off-run had a 72.9 s first lap), so a 5%
difference is within the follower's own spread and a FAIL there would need a second look before it is believed; a
2x speed error would show as -50%. The fade check's race-clock figure (10.04 s against 10.02 s to the same point)
is the tighter speed check. Follow-up: widen the bound to 10% or compare the race clock's advance per flip instead.
(3) The load's flips 5701-5706 keep two vblanks with the option on (not step 5's wait; the load itself); not
chased. (4) The brief's `--pad` should have read `--script`; the acceptance's "by flip 6100" should have read "by
the run's end" (the race clock starts at about 6250): the check does the right thing.
