# 043: The SAS reverb (fidelity difference 12)

Milestone: M8 | Branch: task/043-sas-reverb | Status: OPEN

## Goal
The game asks the SAS mixer for reverb from the race load on (`__sceSasRevType` 5, `__sceSasRevVON` with the dry and
the wet send on, `__sceSasRevEVOL` 0x666 after a ramp from 0xFFF) and the framework accepts the four calls and drops
them, so the race's effects stop dead where the PSP's ring on: at a pause PPSSPP's dump decays over 0.5 s (RMS 2148,
600, 198, 125, 64, 33 in 100 ms steps) and the port's falls to zeros within 100 ms. This task models the reverb in
the framework's software SAS as patch 0018, from the documented algorithm, and checks it against PPSSPP's dump.

## Read first
- CLAUDE.md, docs/fidelity.md (difference 12, its evidence; the audio paragraphs), docs/tasks/041 (Result: the audio
  dump, `tools/audio_compare.py`, the Free Play pause route and figures), docs/verification.md (audio_compare,
  `PURE_AUDIO_WAV`), docs/ppsspp.md ("Audio dumps")
- vendor/portablekit/host/audio/sas_core.hpp and .cpp (the mix: voices, volumes, the grain; "Reverb is not
  modelled"), host/hle/hle_media.cpp (the sceSasCore registrations: the four reverb calls are no-ops; check whether
  `__sceSasSetVolume`'s effect sends, its fourth and fifth arguments, reach the core or are dropped too)
- The documentation, read only: the PSP SDK's sceSasCore reference (`__sceSasRevType` types 0 OFF, 1 ROOM, 2 STUDIO
  SMALL, 3 STUDIO MEDIUM, 4 STUDIO LARGE, 5 HALL, 6 SPACE, 7 ECHO, 8 DELAY, 9 PIPE; `__sceSasRevParam` delay and
  feedback; `__sceSasRevEVOL` the wet volumes; `__sceSasRevVON` the dry and wet switches; `__sceSasSetVolume`'s effect
  sends), and the PlayStation SPU reverb the SAS inherits: psx-spx (nocash), "SPU Reverb Formula" and the "Reverb
  Examples" register tables per preset, at https://psx-spx.consoledev.net/soundprocessingunitspu/ . The PPSSPP
  hardware notes may be read; PPSSPP's source may not, and nothing of it may be copied.

## Deliverable
1. Patch 0018 (`tools/patches.sh export 0018-sas-reverb`): `SasCore` gains a reverb unit (the preset's parameters by
   type, the delay and feedback of RevParam, the wet volumes of RevEVOL, the dry and wet switches of RevVON, each
   voice's effect sends), mixed per grain: dry voices as today, the wet sends through the reverb, added by the wet
   volumes; the four HLE calls and the effect sends of `__sceSasSetVolume` feed it. Type 0 or the wet switch off
   reproduces today's output exactly. Its cost at 44.1 kHz stays well under a grain's time (say the number).
2. The check, repeatable: `tools/sas_reverb_check.sh` runs the port's Free Play pause route headless with
   `PURE_AUDIO_WAV` and compares the pause's decay with PPSSPP's dump of the same route (`ref/audio/free_play_pause.wav`,
   taken once with the driver's `--dump-audio`, git-ignored, its SHA256 in ref/README.md): PASS when the port's RMS in
   each 100 ms step of the first 0.5 s after the pause is within a factor of 2 of PPSSPP's and not zero. Also an
   in-race comparison with `tools/audio_compare.py --locate` over an effects-heavy stretch, reported (not a PASS
   criterion: the AI differs).
3. `tools/wavstats.py` on the Vineta K race unchanged in its activity and with no clipping (the wet mix adds level:
   if it clips where PPSSPP does not, the mix is wrong, not the volume).
4. docs/fidelity.md (row 12 resolved with the before and after decays), patches/README.md (the row), docs/verification.md
   (the check), README.md if a switch is added (`PURE_NO_REVERB=1` to hear the difference is welcome).

## Acceptance criteria
- [ ] `tools/sas_reverb_check.sh` passes; the decay figures before and after are in docs/fidelity.md.
- [ ] `tools/frame_regress.sh --only race_hud` unchanged; `tools/patches.sh check` passes (17 patches); the Vineta K
      race WAV active 12/12 from the race start, no clipping.

## Verify
`tools/patches.sh check && tools/build.sh profile && tools/sas_reverb_check.sh && tools/frame_regress.sh --only race_hud`

## May touch
- vendor/portablekit/host/audio/sas_core.hpp, sas_core.cpp, host/hle/hle_media.cpp via `tools/patches.sh export
  0018-sas-reverb`; patches/; tools/sas_reverb_check.sh (new); tools/ppsspp/routes/ (a route if the pause route needs
  one); ref/README.md (the hash of the new reference); docs/fidelity.md, docs/verification.md, README.md

## Must not touch
- vendor/portablekit/include/psprecomp/, host/gpu/, host/kernel/, src/, config/, tools/frame_regress.sh,
  tools/campaign_sweep.py, tools/audio_compare.py, earlier patches

## Estimated turns
50

## Escalate when
The documented formula and preset, implemented faithfully, leave the pause decay outside a factor of 2 of PPSSPP's at
more than one step (report both decays and what the formula says at those steps), or the reverb needs changes outside
the SAS files (report where).

## Result
Status: PARTIAL. All four deliverables are done and Verify passes, but the brief's escalation condition holds, so
this needs a reviewer's decision. Built exactly as documented, the formula and the HALL preset give a pause decay 2.95
to 13.6 times PPSSPP's, outside the factor of 2 at all five steps. "As documented" here means the SPU's 22050 Hz
between its resampling filters, with sends and wet volumes at unity. Patch 0018 comes within 1.05 to 1.27 of PPSSPP
only with two changes to the documented reverb, each measured against PPSSPP's output: it runs the formula once per
sample at 44.1 kHz, and the sends enter at half volume. Whether to keep them is the reviewer's call.
`PURE_SAS_REVERB_SPU_RATE=1` switches back to the SPU's rate and filters, and `PURE_NO_REVERB=1` turns the reverb off.
The evidence is in docs/fidelity.md, "Difference 12: the SAS reverb".

Changed (branch `task/043-sas-reverb`, from batch/m2 864abf3, 4 commits):
- `patches/0018-sas-reverb.patch`: vendor `host/audio/sas_core.hpp`, `sas_core.cpp` and `host/hle/hle_media.cpp`.
  `tools/patches.sh check` reports 17 patches.
  - `SasReverb` implements psx-spx's formula: the reflections, the combs and the all-pass filters, in the documented
    read/write order with saturation. It has the nine presets by type (PIPE is "Half Echo", the one table left over)
    and RevParam's delay and feedback for ECHO and DELAY (inferred from those two tables).
  - The SPU's 39-tap resampling path is behind `PURE_SAS_REVERB_SPU_RATE`.
  - `SasCore` gains per-voice effect sends, the wet volumes and the dry and wet switches. With type 0 or the wet
    switch off it gives exactly the old output.
  - `__sceSasSetVolume` now passes its fifth and sixth arguments, and the four Rev calls are wired in.
  - `PURE_TRACE_SAS` prints each change of the sends and of the Rev calls. `PURE_TRACE_AUDIO`'s per-second line adds
    `reverb=TYPE reverb_us=N`.
  - Its row is in `patches/README.md`.
- `tools/sas_reverb_check.sh` (new):
  - plays the Free Play pause route headless with `PURE_AUDIO_WAV` on an empty memory stick (about 20 s)
  - finds where the held effects end after START in both mixes
  - compares ten 100 ms steps of the tail with `ref/audio/free_play_pause.wav` and checks the first five (PASS when
    each is within a factor of 2 and non-zero)
- `ref/README.md`: how the PPSSPP dump was taken and its SHA-256 (6487ea24...0b70). The WAV itself is git-ignored.
  A second PPSSPP run gave the same samples.
- `docs/fidelity.md`: the intro and row 12 (resolved, with the before and after decays) and a new section, "Difference
  12: the SAS reverb".
- `docs/verification.md`: the check's section.
- `README.md`: the two switches and the check.

Verify output (`tools/verify_task.sh 043`, last 20 lines):
```
  300-400        63       60       1.05     ok
  400-500        35       31       1.13     ok
  500-600        18       16       1.11     (shown only)
  600-700         9        8       1.10     (shown only)
  700-800         5        4       1.19     (shown only)
  800-900         2        2       1.26     (shown only)
  900-1000        1        1       1.21     (shown only)

sas_reverb_check: PASS (the first 5 steps within a factor of 2 of PPSSPP's, none zero)
frame regression 2026-10-07 09:01, commit 2671b51+changes, shell headless (PURE_SHELL), backend metal (PURE_GE_BACKEND), measured column metal
extra environment: none
data directory: out/data/frame_regress
run main_menu+single_race: 6046 flips ...
run main_menu+single_race: run_boot exit 0, frame 6046 reached: yes, 5 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-ab5daff329771058a/out/regress/main_menu+single_race.log

scene       frame  fraction  limit  tol  measured   delta  result
race_hud     6016    0.0148   0.10   32    0.0149 -0.0001  PASS

frame regression: PASS, 1/1 scenes pass, shell headless, backend metal (0m 5s)
verify 043: PASS
```

**The decay figures.** RMS of each 100 ms step from where the held effects end, with port/PPSSPP in brackets. The
port's held effects end at 558.085 s, 150 ms after START. PPSSPP's end at 480.609 s, 130 ms after START. The port is
deterministic, so every variant ends at the same moment:

| | 0-100 ms | 100-200 | 200-300 | 300-400 | 400-500 | steps outside 2x |
|---|---|---|---|---|---|---|
| PPSSPP | 383 | 194 | 116 | 60 | 31 | |
| before (no reverb) | 254 (0.66) | 0 | 0 | 0 | 0 | 4, zero |
| as documented: 22050 Hz with the filters, unity | 1128 (2.95) | 833 (4.29) | 715 (6.17) | 535 (8.92) | 422 (13.61) | 5 |
| the formula at 44100 Hz, unity | 864 (2.26) | 468 (2.41) | 261 (2.25) | 126 (2.11) | 70 (2.25) | 5 |
| after (patch 0018: 44100 Hz, half sends) | 487 (1.27) | 234 (1.21) | 131 (1.13) | 63 (1.05) | 35 (1.13) | 0 |

From 500 ms to 1 s, patch 0018 gives 18, 9, 5, 2, 1 against PPSSPP's 16, 8, 4, 2, 1.

**What the documented formula gets wrong.**
- **The slope.** At 22050 Hz the tail falls by 1.2 to 1.4 every 100 ms, against PPSSPP's 1.7 to 2.0. At 44100 Hz it
  falls by 1.8 to 2.1. No gain fixes the 22050 Hz version: its ratio to PPSSPP's grows from 3 to 14 over half a second.
- **The level.** At 44100 Hz with unity sends, the tail is 2.1 to 2.4 times PPSSPP's at every step of the first
  second. The steady effects level shows the same factor independently. Over 250 s of the Free Play idle, PPSSPP's mix
  minus the port's music (aligned to the sample, -74.78293 s) has RMS 2819, against the port's sceSas channel:

  | Port | RMS | port/PPSSPP | per second |
  |---|---|---|---|
  | without the reverb | 2752 | 0.976 | |
  | unity sends | 3093 | 1.097 | 1.07 to 1.12 |
  | half sends (patch 0018) | 2840 | 1.008 | 0.99 to 1.02 |

**The in-race comparison.** These figures are reported, not checked, because the AI differs. The PPSSPP side is a
Vineta K Single Race dump with Cross held (`frontend.txt` + `vineta_k_start.txt` + `vineta_k_hold_cross.txt`). The
port side is `main_menu.txt` + `single_race.txt`, headless. `audio_compare.py --locate` aligns the port's music at an
offset of -77.83447 s (correlation 0.38 at 210 s, 0.68 at 240 s).

| Measure (window) | PPSSPP | Port with reverb | Port without |
|---|---|---|---|
| Effects RMS, 40 s with the AI (PPSSPP: mix minus music) | 2003 | 2003 (1.000; 0.86 to 1.16 per second) | 1964 (0.980) |
| Mix RMS, 46 s from GO, port/PPSSPP | | 1.003 | 0.991 |
| `--locate` waveform correlation | | 0.74 at the countdown, 0.25 to 0.68 later | 0.75 at the countdown, about the same later |

`tools/wavstats.py` from GO: the mix and the sceSas channel are active 49 of 49 seconds with no clipping, with and
without the reverb. The mix peak is 21032 against PPSSPP's 21485.

**Cost per grain.** The reverb takes 790 us of host time per second of race audio (`reverb_us`, averaged over 245
seconds). The game's grain is 256 frames, 5.8 ms of sound, so that is about 4.6 us per grain, 0.08% of its time. A
standalone loop of the HALL unit measured 4.2 us per 256 frames. All on the M4 Pro.

Open questions:
1. **Keep the two changes?** The 44.1 kHz step is fixed by the slope of the decay. The half send is one constant fixed
   by the level, and it fits both the tail (every step of the first second) and the steady level of the idle and the
   race. Neither comes from documentation I could read. A PSP SDK sceSasCore reference, if one is available, might say
   where the half comes from (the send, the wet volume's unity, or the unit's output). The patch takes it at the send.
2. **Inferences no game here exercises.** Three parts of the patch are inferred: RevParam's mapping for ECHO and DELAY
   (feedback as vWALL = -(feedback << 8), delay as a linear scale of the tables' FFAh distance), PIPE as psx-spx's
   "Half Echo", and treating type -1 (the game's first call) as OFF. Wipeout Pure uses HALL with RevParam (0, 0) only.
3. **The menus.** The unit runs whenever a type is set, including in the menus, where the wet switch is off. So when
   the race switches the wet on, it hears whatever tail the menus left in the ring. Whether a PSP clears or freezes
   the ring with the wet off is not known, and whether that tail is audible at the race start was not measured.
4. **The check's tail-start rule.** It is a heuristic tuned to this route: a drop under 0.6 of the five blocks
   before it, once the music has stopped. It finds the same moment in all three port variants and in PPSSPP, but
   another route would need its own look.
5. **Not measured again.** The attract demo's clipping (difference 9) was not re-measured with the reverb.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
