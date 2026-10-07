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
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
