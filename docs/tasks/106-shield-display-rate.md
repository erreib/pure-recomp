# 106: The shield effect at the display's rate (GitHub issue 2)

Milestone: E8 (D-022) | Branch: task/106-shield-display-rate from batch/m2 | Status: OPEN

## Goal
GitHub issue 2 (2026-10-22, RussDCA, an M4 Pro Mac mini at 120 fps), "Infinite shield (visuals only)": in a race,
after a Shield is picked up the shell effect (the one that sweeps from the ship's nose back over it) does not show;
after the first wall contact it shows and never stops, for the rest of the race, on the player's ship and on the
opponents'. Damage still lands, so the shield itself ends on time and only the picture is stuck. Erik reproduced it
on the Mac (2026-10-23, Metal, internal scale 6, the HD pack, Texture detail and Smooth flashes on) and found it
follows the Display rate row: at Display (the race at 119.40 Hz) it sticks, at Original it behaves. When this task
is done the shield effect looks the same at Display as at Original, at any display rate the row runs, and nothing
else in the race changes.

The suspect (a guess, not read in the code): the effect steps its animation in whole 60 Hz frames taken from dt
(`(int)(dt * 60)` or the like), which is 1 at 60 Hz and 0 at 120, so the build-up never starts, the contact sets a
visible state outright, and the fade never advances. A vblank-count step or a test of a value for equality after
a dt-sized step would also fit. Find out which; do not assume it.

## Read first
- docs/timing.md: "E8: the display rate (task 089)" (what runs at the display's rate and why; frames drive the
  frontend's transitions) and "The game's clock in a race (task 046)" (`FUN_08804390`'s dt, clamped, in 1 ms steps
  on the port's clock; `FUN_08893284` hands it to every object).
- src/profile/enhancements.cpp, the E8 hook (the period set in the `sceGeDrawSync` wrap) and its gate (the race
  backend at `DAT_08a8c5f4`).
- src/profile/aspect.cpp: the function-override pattern (the generated body found through `Registrations`, the
  override registered once, why not before it is needed, the `[aspect]` lines).
- docs/tracks.md, "The shield": the shield value at `be::Ship` +0xF8 and the functions that touch it (that is the
  energy bar, not the pickup; read it for the ship object's layout and for `PURE_WATCH_SHIP`).
- config/function_labels.csv: `FUN_08946054` (`LinkObj.h;Shield.cpp`, the only function labelled from Shield.cpp;
  it is reached from the ship's update at 0x08924344), `FUN_0884bf3c` (`WeaponManager.cpp`).

## Facts
- The texture `in_game/effects/ship/absorb_surface` (an HD pack name) is first drawn in the race when a shield
  shows: likely the shell's. It is a lead to the draw, not proof.
- Ghidra is on the Mac: `tools/ghidra_headless.sh script Decompile <outfile> <hexaddr>...` and `script Callers`.
- `PURE_DISPLAY_RATE=1 PURE_DISPLAY_HZ=N` runs the race at N Hz headless (docs/developing.md); `tools/run_boot.py
  --shell headless --shots DIR` writes frames headless. The Vineta K drive route (config/pad_scripts/drive/) races
  against seven opponents, who use shields.
- Game data and frames never enter the repository: keep shots under `out/106/`.

## Deliverable
1. **The diagnosis** (in Result): the function(s) that step the shield effect, what they step it with, and why it
   stalls at 119.40 Hz and not at 59.94, with addresses and the decompiled lines. Then a census: other functions
   that convert dt to whole frames, or step by the vblank count, in the same way (grep the decompile of the
   functions dt reaches through `FUN_08893284`'s callees as far as is cheap; list them with what they drive, and
   say which you looked at and which you did not). Do not fix those here; they are the next brief's.
2. **A trace**, `PURE_TRACE_SHIELD=1` (test-only, src/profile/): once a frame while a shield effect is live, the
   frame, the ship's index and the effect's step state (`[pure] shield frame N ship K ...`), so both rates can be
   compared from a headless run.
3. **The fix**, in src/profile/ only, by the aspect pattern: an override of the stepping function that makes the
   step follow time at any rate (for example carry the fraction of a 60 Hz frame from one call to the next, per
   effect, so two 119.40 Hz frames make one step, or run the generated body only when a whole 60 Hz frame of dt has
   gathered, whichever the code makes exact). Installed only while the display rate is above the PSP's, as E8's
   hook decides, so Original runs exactly the generated code. One line when it goes in (`[pure] shield step:
   ...`). An off switch: `PURE_SHIELD_STEP=0` keeps the generated code at Display (docs/developing.md row).
4. **A check**, `tools/shield_check.sh`: the drive route headless at Original and at `PURE_DISPLAY_HZ=120` with
   `PURE_TRACE_SHIELD=1`; PASS when every shield effect seen in the 120 lane builds up and ends, and its life in
   seconds is within 10% of the Original lane's median (or of the decompile's constant, if the routes do not line
   up). docs/verification.md row.
5. docs/timing.md: a subsection "The shield effect (task 106)" under E8 with the diagnosis, the fix and the
   census; docs/status.md: the E8 row and the Next bullet for issue 2.

## Acceptance criteria
- [ ] Result names the stepping code and the cause, with the decompiled lines.
- [ ] At 120 headless the trace shows the effect building up after a pickup and ending, as at Original.
- [ ] At Original the override is not registered (no `[pure] shield step` line) and the run's dispatches are
      unchanged (`tools/frame_regress.sh` headless and `tools/display_rate_check.sh --race`, PASS).
- [ ] `PURE_SHIELD_STEP=0` at 120 brings the stuck effect back (the trace shows it), so the switch is real.
- [ ] The census is in Result, with what was and was not looked at.

## Verify
`tools/build.sh profile && tools/shield_check.sh && python3 tools/docs_check.py`

## May touch
- src/profile/ (a new shield_step.cpp/.hpp, enhancements.cpp's install call, CMake's source list for it)
- tools/shield_check.sh, docs/timing.md, docs/developing.md, docs/verification.md, docs/status.md,
  docs/tasks/106-shield-display-rate.md, out/106/ (never committed)

## Must not touch
`vendor/`, `vendor/portablekit/include/psprecomp/`, `generated/`, the code generator, the kernel scheduler,
`tools/regen.sh`, `main`, src/gpu/ (it is not the renderer: Original draws it right).

## Estimated turns
50. Commit at each stage (the diagnosis in Result first, then the trace, then the fix and the check), so a stop at
the turn limit resumes from the branch.

## Escalate when
- The stepping is not in one function the override can wrap (it is inlined into the ship's update or a shared
  effect manager that also steps other effects): stop after the diagnosis, BLOCKED, with what a fix there would
  change.
- The cause is not a frame-sized step (the effect follows the vblank count through the kernel, or its life is set
  in flips by code outside the race): stop after the diagnosis, BLOCKED.
- The fix changes anything at Original, or any race figure `tools/display_rate_check.sh --race` bounds.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
