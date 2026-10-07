# 041: The hitches, the music gaps and the demo's clipping: checked against PPSSPP (fidelity differences 7, 8, 9)

Milestone: M8 | Branch: task/041-hitches-and-audio-checks | Status: MERGED (b9fd4ad, 2026-10-07)

## Goal
Three findings of the audit are "to check": the game freezing 0.1 to 0.3 s now and then with a gap in the sound (12
of 46 cells, at no fixed place), the race music stopping about 2 s when it changes tracks at 5:24 of the race music
and 3.9 s at Free Play's finish, and the attract demo's sound clipping. Each is either the game's own behaviour
(PPSSPP does the same) or the port's. This task settles each with PPSSPP's audio dump and an idle-machine run, and
fixes what is the port's if it is small, or reports it as a task.

## Read first
- CLAUDE.md, docs/fidelity.md (differences 7, 8 and 9, their evidence, the hitches column of the matrix, the
  `out/fidelity-hitch/` note), docs/tasks/033 (Result: `PURE_METAL_TRACE`, `tools/frame_times.py`, the long-frame
  causes), docs/ppsspp.md (the driver; how to run a route with PPSSPP's audio dump, `DumpAudio` in its settings or
  the driver's option: read the driver), tools/wavstats.py, docs/tasks/013 (the WAV capture: `PURE_AUDIO_WAV`)
- src/hle/audio_capture.cpp (the capture's channels and underrun lines), vendor/portablekit/host/audio/ (the sink,
  the SAS mix; what "underrun" means in the log), host/hle/hle_atrac.cpp (how a new music track is fed)

## Deliverable
1. Hitches (7): a player-like run, the Metal shell in a window, no probe lines, no WAV capture, nothing else on the
   machine, with `PURE_METAL_TRACE`: the Vineta K race through the sweep (`--shell metal`, `--no-damage`) twice, and
   `tools/frame_times.py` on each. If frames over 100 ms appear, their columns say where (the trace names the host's
   waits, the backend's work, and `other_ms` for the game and the HLE); then the same run with `PURE_AUDIO_WAV` and
   with the probe lines back, to show which of the three makes them. Fix it if it is the port's and small (a wait that
   can be moved, a buffer that can grow); otherwise the finding goes to docs/fidelity.md with the numbers.
2. Music gaps (8): PPSSPP's audio dump of a long race (the route that reaches 5:30 of race music) and of a Free Play
   finish, against the port's WAV of the same routes (`tools/wavstats.py` per second, and the sample-level gap at
   the track change and the finish): the same gaps mean the game's own; a gap only in the port means the HLE's ATRAC
   feeding (then say which call sequence differs, with `PURE_TRACE_ATRAC`).
3. Demo clipping (9): PPSSPP's audio dump of the attract demo (the main menu left for 30 s) against the port's: the
   peak levels and the clipped-sample counts side by side; if only the port clips, the SAS mix level in the framework
   is the suspect (report the level and what PPSSPP's output implies; a one-line patch if it is a constant).
4. docs/fidelity.md: the three rows resolved (faithful, fixed, or a task with evidence); docs/verification.md if a
   check becomes repeatable (an audio comparison script under tools/ is welcome: `tools/audio_compare.py A.wav B.wav
   --from S` printing per-second activity and the longest silences of each).

## Acceptance criteria
- [ ] Each of the three has a verdict with evidence in docs/fidelity.md: the same in PPSSPP, or the port's with the
      cause named (and fixed, or a task).
- [ ] If a fix is made: `tools/frame_regress.sh` unchanged and `tools/wavstats.py` on the Vineta K race unchanged
      (active 12/12 from the race start, no clipping).

## Verify
`python3 tools/audio_compare.py --selftest && tools/frame_regress.sh --only race_hud`

(`--selftest` checks the tool on two generated WAVs; the comparisons themselves are reported in docs/fidelity.md.)

## May touch
- tools/audio_compare.py (new), tools/ppsspp/routes/ (audio-dump routes), tools/ppsspp/ (the driver: an audio-dump
  option if it has none, with its docs/ppsspp.md row), docs/fidelity.md (differences 7 to 9),
  docs/verification.md; for a small fix: src/hle/audio_capture.cpp, or a vendor patch to host/audio/ or host/hle/hle_atrac.cpp
  via `tools/patches.sh export 0018-<cause>` with its patches/README.md row

## Must not touch
- vendor/portablekit/include/psprecomp/, host/gpu/, host/kernel/, src/gpu/, src/host/, src/profile/, tools/frame_regress.sh,
  tools/campaign_sweep.py, config/, ref/

## Estimated turns
50

## Escalate when
PPSSPP's audio dump cannot be taken through the driver (report what the driver offers and what the settings file
needs; the comparison then waits), or the hitches appear only with the sweep's probe lines (report: that is the
test harness, and the finding closes as not the port's).

## Result
Status: DONE. All three differences are settled, and none of them is the port's. The hitches (7) come from the
headless test runs. The music's 2 s stop and Free Play's 3.9 s (8) happen the same way in PPSSPP. PPSSPP's attract
demos clip as much as the port's (9). Nothing in the game's code paths was changed. The task also found a new
difference: the game asks for SAS reverb in races, and the framework drops it (difference 12, docs/fidelity.md).
docs/fidelity.md has the full evidence under "Differences 7 to 9" (2026-10-07).

Changed (branch `task/041-hitches-and-audio-checks`, from batch/m2 dd25b78, 8 commits):
- `tools/audio_compare.py` (new):
  - compares two WAVs, each with its own window start
  - per second: RMS, peak and clipped samples, with a mark where only one of the two is active
  - the longest silences in 10 ms blocks
  - `--detail S:E` gives 100 ms rows
  - `--locate T:LEN:FROM:TO` finds a stretch of B inside A by normalised cross-correlation. This is how the port's
    music channel was found inside PPSSPP's mix-only dump.
  - `--selftest` checks the tool on generated WAVs, including a stretch hidden under louder noise.
- `tools/ppsspp/ppsspp_ctl.py`: new `run --dump-audio WAV`.
  - For the session it sets `DumpAudio = True`, `SaveLoadResetsAVdumping = False` and `[Sound] Enable = True`.
  - At the end it moves PPSSPP's `PSP/AUDIO/*.wav` to WAV and repairs the RIFF sizes if PPSSPP did not close the file.
  - The report gets an `audio_dump` entry, and `ini show` lists the keys.
- `tools/ppsspp/routes/free_play_idle_end.txt` (new): Free Play with the ship left on the grid past the race music's
  first track change, then END SESSION from the pause menu.
- `docs/fidelity.md`:
  - rows 7 to 9 resolved, and row 12 added (the reverb)
  - the intro count updated, and the audio paragraphs annotated
  - the pre-warm follow-up rewritten with the trace's evidence
  - new section "Differences 7 to 9: checked in a window and against PPSSPP's audio"
- `docs/ppsspp.md`: an ini-table row for `--dump-audio` and an "Audio dumps" section.
- `docs/verification.md`: an `audio_compare.py` section.

Verify output (`tools/verify_task.sh 041`, last 20 lines):
```
selftest: ok   A's second silence is 200 ms at 4.50 s
selftest: ok   B's longest silence is 500 ms at +2.50 s (3.50 s in the file)
selftest: ok   A has 10 clipped samples, B none
selftest: ok   A's peak is 32767, B's the tone's (7999)
selftest: ok   second 2 is silent in A and active in B, the only such row
selftest: ok   the summary counts that one row
selftest: ok   --locate finds a stretch under louder noise to the sample (A2 2.5 s)
selftest: ok   a missing file is refused
PASS
frame regression 2026-10-07 04:39, commit 700daa6, shell headless (PURE_SHELL), backend metal (PURE_GE_BACKEND), measured column metal
extra environment: none
data directory: out/data/frame_regress
run main_menu+single_race: 6046 flips ...
run main_menu+single_race: run_boot exit 0, frame 6046 reached: yes, 5 s, log /Users/erreib/dev/pure-recomp/.claude/worktrees/agent-aab7e5fa583b23e6e/out/regress/main_menu+single_race.log

scene       frame  fraction  limit  tol  measured   delta  result
race_hud     6016    0.0148   0.10   32    0.0149 -0.0001  PASS

frame regression: PASS, 1/1 scenes pass, shell headless, backend metal (0m 5s)
verify 041: PASS
```
No fix was made, so the acceptance's `frame_regress`/`wavstats` clause does not apply.

**Difference 7 (the hitches): the headless test runs, not a player's run.**

The machine was not idle, and the other load was not this task's to stop:
- a browser renderer at 100%, suggestd at about 90%, mediaanalysisd, mds_stores, and a Steam helper at 280% at the
  start
- load-average medians of 5.7 to 7.8 per run
- 44.5 GB of the 45 GB swap in use, on 24 GB of memory

The display was asleep, so no windowed picture reached the screen. Every run was alone, and every run had
`PURE_METAL_TRACE`. The table gives race-window frame times in ms:

| Run | Settings | Frames | Mean | Median | p99 | Longest | >=50 | >=100 | Longest frame's columns | 45 ms clock jumps; underruns ch1/ch2 |
|---|---|---|---|---|---|---|---|---|---|---|
| S1 | Single Race Vineta K, sweep `--shell metal --no-damage --sound` (window, audio device on, paced from 0, probe lines, no WAV) | 11519 | 16.72 | 16.69 | 18.64 | 50.89 | 1 | 0 | GPU depth wait 44.4 | 0; no WAV |
| P1 | same cell, PureNative launched directly with stdout to a file, S1's steering replayed (window, audio on, no probe lines, no WAV) | 11519 | 16.80 | 16.68 | 19.00 | 39.27 | 0 | 0 | GPU wait 20.1, submit 14.6 | no probe; no WAV |
| P2 | as P1 | 11519 | 16.71 | 16.67 | 18.70 | 39.05 | 0 | 0 | GPU depth wait 33.1 | no probe; no WAV |
| W1 | as S1 plus `PURE_AUDIO_WAV` | 10869 | 16.81 | 16.70 | 19.48 | 62.81 | 1 | 0 | GPU depth wait 57.5 | 0; 0 / 0 |
| W2 | Free Play Vineta K, as S1 | 6355 | 33.37 | 33.37 | 34.67 | 70.51 | 1 | 0 | other 59.2 | 0; no WAV |
| A1 | Single Race, sweep `--no-damage` + WAV, headless and silent, paced from 6100 (the matrix's way) | 11459 | 16.85 | 16.70 | 32.30 | 233.83 | 7 | 1 | submit 59.4 (no pipeline), other 169.5 | 1 (101 ms); 69 / 17 ms |
| A2 | Free Play, as A1 | 5995 | 33.42 | 33.36 | 35.11 | 251.11 | 6 | 1 | pipeline 242.7 (2 not in the pre-warm list, cold cache) | 1 (250 ms); 190 / 174 ms |
| A3 | A2 again, warm cache | 6475 | 33.42 | 33.34 | 35.16 | 323.44 | 10 | 2 | submit 163.9 (texture 69.2, nothing decoded), other 130.4; and 115.2 (other 109.0) | 1 (133 ms); 84 / 57 ms |

What the runs show:
- **Windowed runs: no frames of 100 ms or more.** That holds over 16.2 minutes of race, with or without probe lines
  and the WAV capture. The longest frames come from the SIGNAL depth wait (44 to 58 ms) and, once, 59 ms outside the
  backend.
- **Headless runs: four such frames in 10.2 minutes**, with the matrix's signature: virtual-clock jumps and underruns
  on the effects and music channels.
- **Cause 1, host contention.** In three of the four, every part of the frame grew at once with nothing made or
  decoded. A headless PureNative runs all its threads at scheduling priority 31, while a windowed one runs its main
  thread at 46 and the rest at 37.
- **Cause 2, a cold-cache pipeline compile.** In the fourth, two render pipelines missing from
  `config/metal_pipelines.txt` were built on a cold shader cache in 242.7 ms. The same two took 0.76 ms in W2 and A3.
- **No fix in this task's files.** The pre-warm entries would go in `config/`, which this task must not touch. The
  follow-up is recorded in docs/fidelity.md.

**Difference 8 (music gaps): the game's own.**

PPSSPP dumped the same Free Play idle route (`frontend.txt` + `free_play_start.txt` + `free_play_idle_end.txt`,
495.5 s). The port ran the same menus headless with `PURE_AUDIO_WAV` and `PURE_TRACE_ATRAC` (584.7 s).

The track change:
- **The silence is part of the track.** The first race track is 14,380,032 samples (326.08 s) and ends in a fade and
  2.15 s of digital silence. The port decodes every frame of it to the end, none past the data the game added.
  - Port music channel: below RMS 100 from 520 s, then zero runs of 177 ms at 524.755 s and 2153 ms at 525.179 s.
- **PPSSPP plays the same samples.** `--locate` found the port's music inside PPSSPP's mix at offset -74.78293 s
  both at port 215 s (correlation 0.44) and at port 500 s (0.67).
- **PPSSPP switches tracks 38.5 ms sooner.** After the change the offset is -74.74447 s (528 s: 0.34; 535 s: 0.45),
  so track 2 starts 38.5 ms (1696 samples) sooner in PPSSPP. The port's share of that is a 26 ms underrun at 527.30
  s. It lies inside the track's own silence and is not audible.
- **The later change is the same thing.** The matrix's change at 755 s is track 2's end (227.86 s).

Free Play's finish:
- **The pause silences both.** START silences the music and the effects in both, and the end screen's sound returns
  3.9 s later in the port and 4.0 s later in PPSSPP. Between the menu sounds the silences are 1220/1240/1210 ms
  (port, all zero) and 970/1250/1250 ms (PPSSPP, at RMS 1).
- **Per-second activity matches.** From the race music's start the two windows, aligned by the music, are active in
  the same 367 of 368 seconds, with 0 seconds where only one is active. Neither clips (peaks 21403 port, 24186
  PPSSPP), and the port's music channel is active 347 of 354 s.

**Difference 9 (attract demo clipping): the game's own.**

PPSSPP's frontend route idled to vblank 22000 (367.0 s). The port's `main_menu.txt` ran to flip 17000 (381.1 s), and
to 13500 as in the audit, where it reproduced the audit's 2611 (mix) and 3474 (channel 1) exactly.

The game picks the demo tracks itself, so the content differs: PPSSPP played Vineta K, Blue Ridge and Vineta K;
the port played Modesto Heights and Citta Nuova.

| Demo | Peak | Clipped samples | Fraction | Clipped seconds | Loudest second RMS |
|---|---|---|---|---|---|
| PPSSPP, demo 1 | 32768 | 699 | 0.000065 | 5 | 11817 |
| PPSSPP, demo 2 | 32768 | 2236 | 0.000209 | 11 | 13226 |
| Port, demo 1 | 32768 | 2611 | 0.000246 | 10 | 11863 |
| Port, demo 2 | 32768 | 836 | 0.000111 | 5 | 10735 |

From the main menu on, the totals are 2935 clipped samples (0.000120) for PPSSPP and 3447 (0.000166) for the port.
Both mixes are active every second (277/277 and 235/235), and their longest silences are the demo loads.

Where the content is the same, the levels agree:
- the menu music is at RMS 1686 in both
- over 250 s of the Free Play idle the RMS is 3633 against 3682, with the port's per-second RMS at 0.966 to 1.004 of
  PPSSPP's (mean 0.986)

So the SAS mix level is not the cause.

Open questions:
1. **Difference 12, the SAS reverb (new, medium).** The game calls `__sceSasRevType` 5, `__sceSasRevVON` with the
   wet send on, and `__sceSasRevEVOL` 0x666 from the race load on. The framework drops all four. PPSSPP's dump fades
   over 0.5 s at a pause where the port's stops dead. Implementing it is a framework task; a PPSSPP race dump with
   `audio_compare.py` is the check.
2. **Pre-warm entries (small).** Add the nine pipelines every 30-fps run makes by a draw to
   `config/metal_pipelines.txt`: six at the race load and two or three once in the race. On a cold cache they are
   the one hitch a player could meet.
3. **38.5 ms later track switch (not chased).** The port's second race track starts 38.5 ms later than PPSSPP's,
   inside the first track's 2.15 s silence. The cause is likely the sceAudio blocking/queue timing around the switch.
4. **The brief's settings could not be met exactly.** The brief asked for player-like runs "through the sweep", but
   the sweep cannot drop its probe lines (the follower steers from them), so P1 and P2 launched the game directly
   with S1's steering replayed. The windows never reached the screen because the display was asleep at 03:20 to
   04:30; `caffeinate -u` did not wake it.


## Review
Verify rerun: PASS from the main checkout at b9fd4ad (2026-10-07): `tools/verify_task.sh 041` (audio_compare
selftest PASS; race_hud 0.0148 against its measured 0.0149). No code of the port changed and no patch was added, so
the full suite stands at task 040's rerun.

Spot-read: tools/ppsspp/ppsspp_ctl.py (the dump settings go through the existing session context manager with the
driver's and mute settings, so they are restored after the run; only the WAV new or grown during the run is moved
out of the memstick, others are left in place; the RIFF repair rewrites only the data and RIFF sizes of a file
PPSSPP did not close; `--dump-audio` refuses `--keep-running`), tools/audio_compare.py (the selftest covers each
measure the comparisons use: activity, silences, clipping, peaks, the one-sided rows and `--locate` under noise),
docs/fidelity.md rows 7, 8, 9 and the new 12. Files outside May touch: none.

Merged: b9fd4ad into batch/m2 (`git merge --no-ff`).

Notes: the brief's "through the sweep" could not drop the probe lines (the follower steers from them), so the two
player-like runs launched the game directly with the sweep's steering replayed, which is the closer imitation of a
player anyway. The machine was under heavy load during the runs (a browser renderer, a Steam helper, 44.5 GB of
swap in use on 24 GB) and the display was asleep, so no window reached the screen; the frame times are host
wall-clock and the windowed-against-headless contrast holds under that load, but a run with the display awake on
an idle machine would be the final word on a player's experience. Open items go to docs/status.md: the SAS reverb
(difference 12, a framework patch: the game sends type 5, both sends on, volume 0x666), the pre-warm list's nine
missing pipelines (the one hitch a player could meet, on a cold shader cache), and the 38.5 ms later track switch.
