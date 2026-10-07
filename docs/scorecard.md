# The accuracy scorecard

`tools/scorecard.py` (task 044) answers "how close is the port to the original" in numbers that can be re-run after
every change: six categories, each measured on the port headless and compared with PPSSPP (the oracle, its side taken
once and kept under `ref/scorecard/`, hashes in `ref/README.md`) or with the game's own facts. Every row has a grade:
`faithful`, `close` or `differs`, by the threshold in its Threshold column; a category's grade is its worst graded row.
Three marks stand in for a grade where none can be given and do not count towards the category's: `no reference`
(the PPSSPP side is missing: refresh it), `not measured` (no instrument exists) and `accepted (D-011)` (difference 6,
the faster race loads, which Erik decided to keep). The two differences the audit left open for a decision:
difference 6 (the race load) is that accepted row; difference 5 (saves plain where the PSP enciphers them) was fixed
by task 045 (patch 0019), so the Saves rows compare enciphered saves, the data file by its decrypted contents.

| Category | What is compared | Thresholds |
|---|---|---|
| Pictures | `tools/frame_regress.sh`'s 18 scenes (its summary) and the first race frames of Blue Ridge, Sinucit and Sebenco Climb (docs/fidelity.md item 3), the fraction of pixels over the tolerance against the PPSSPP capture | faithful within 0.005 of the scene's measured column, close up to its limit, differs above it |
| Trajectories | per circuit (12, Vector, unlock switch), the player's ship with Cross held from the countdown and no steering: PPSSPP's race records (sampled as `tools/pp_lines.py` does, each read twice and kept when both agree) against the port's `PURE_WATCH_GRID` records, clock-aligned (the port's positions interpolated at PPSSPP's race clocks) | the first clock more than 1 m apart is reported; graded on the largest distance over the first 20 s: faithful under 1.5 m, close under 5 m. The AI ships only if two PPSSPP runs of Vineta K agree at every common clock (under 0.01 m) |
| Timing | flips per race-clock second per mode (60 in Single Race and Tournament, 30 in Time Trial, Free Play and Zone); the two-vblank stretches of a follower-driven Vineta K race against PPSSPP's (`tools/fidelity_audit.py --ppsspp-race`); the race load | flips: faithful within 2% of 60 or 30, close within 5% (the stretches, the game's own, lower the 60-fps modes by half their share of the race clock); stretches: faithful when the counts differ by at most 1, close by at most 3; the load: accepted (D-011) |
| Audio | the main menu's music over 60 s (L pressed every 20 s keeps the attract demo away; it makes no sound); one Single Race per league (Vineta K, Sinucit, Sagarmatha), Cross held, 60 s from GO: the port's `PURE_AUDIO_WAV` against PPSSPP's audio dump | correlation (`audio_compare.py --locate`, the port's music in PPSSPP's mix): faithful at 0.6 or more, close at 0.3; RMS ratio: faithful within 0.95 to 1.05, close within 0.9 to 1.1; seconds where both mixes or neither are active: faithful at 98% or more, close at 90%; clipping: faithful when the port's clipped share is at most PPSSPP's + 0.0001, close at + 0.001 |
| Saves | the profile `tools/save_roundtrip.sh`'s first run makes (`main_menu.txt` on an empty stick; made here headless) against PPSSPP's save of the same profile (NAME0000, `save_yes.txt`) | names, sizes, PARAM.SFO's fields and ICON0.PNG's bytes: faithful when equal (ICON0.PNG close when only the encoding differs), differs otherwise; the data file by size, and by its contents decrypted through the framework's load path (`tools/save_interchange.sh --check`, task 045): faithful when identical, close when only words holding user-RAM addresses differ |
| Coverage | the matrix's 46 cells (`tools/fidelity_audit.py`'s cell results, reused from `out/035-wip/fidelity`, never run here), the 278 imports by state, the GE commands the framework still ignores (this run's exit list), the functions entered | halts, stubs, unsupported instructions, skipped draws: faithful at 0; imports: close while a constant or a documentation-only answer stands in; GE: close while every command left is one no draw of the game uses |

Run it: `python3 tools/scorecard.py --quick` (pictures, timing from the matrix's cells, saves, coverage; about a
minute) or `--full` (all six, with fresh sweep cells for timing; about 18 minutes; a full run of every category
rewrites this file). `--only CATEGORY[,...]` runs some. Refresh the PPSSPP side: `python3 tools/scorecard.py
--refresh-references [CATEGORY]` (about an hour for all; docs/verification.md, "The accuracy scorecard").

## --full run of 2026-10-07 11:57, commit db10191 (17m 38s)

| Category | Grade | Rows: faithful / close / differs / other | Wall time |
|---|---|---|---|
| Pictures | faithful | 21 / 0 / 0 / 0 | 42 s |
| Trajectories | differs | 14 / 1 / 10 / 0 | 148 s (task 046's run with the race clock, below) |
| Timing | faithful | 6 / 0 / 0 / 1 | 721 s |
| Audio | faithful | 11 / 0 / 0 / 0 | 119 s |
| Saves | close | 14 / 1 / 0 / 0 | 3 s |
| Coverage | close | 6 / 3 / 0 / 1 | 0 s |

### Pictures: faithful (2026-10-07 11:57, commit db10191)

| Measure | Port | Reference | Difference | Grade | Threshold | Note |
|---|---|---|---|---|---|---|
| lang (frame 690, tol 24) | 0.0002 | measured 0.0002, limit 0.07 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| title (frame 1750, tol 24) | 0.0002 | measured 0.0002, limit 0.05 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| profile (frame 2100, tol 24) | 0.0000 | measured 0.0000, limit 0.07 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| main_menu (frame 4700, tol 24) | 0.0106 | measured 0.0106, limit 0.05 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| race_hud (frame 6016, tol 32) | 0.0148 | measured 0.0149, limit 0.10 | -0.0001 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| single_player (frame 4765, tol 24) | 0.0000 | measured 0.0000, limit 0.05 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| class_select (frame 4990, tol 24) | 0.0000 | measured 0.0000, limit 0.07 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| league_select (frame 5185, tol 24) | 0.0000 | measured 0.0000, limit 0.08 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| track_select (frame 5390, tol 24) | 0.0000 | measured 0.0000, limit 0.06 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| team_select (frame 5600, tol 24) | 0.0000 | measured 0.0000, limit 0.06 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| tt_track_select (frame 5375, tol 24) | 0.0000 | measured 0.0000, limit 0.06 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| tt_hud (frame 5890, tol 32) | 0.0112 | measured 0.0112, limit 0.12 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| fp_track_select (frame 5375, tol 24) | 0.0000 | measured 0.0000, limit 0.06 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| fp_hud (frame 5890, tol 32) | 0.0113 | measured 0.0116, limit 0.11 | -0.0003 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| tournament_select (frame 5185, tol 24) | 0.0000 | measured 0.0000, limit 0.08 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| zone_track_select (frame 4975, tol 24) | 0.0000 | measured 0.0000, limit 0.05 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| zone_hud (frame 5260, tol 32) | 0.0121 | measured 0.0121, limit 0.09 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| zone_change (frame 5679, tol 32) | 0.0353 | measured 0.0353, limit 0.10 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| blue_ridge_hud (frame 6016, tol 32; docs/fidelity.md item 3) | 0.0247 | measured 0.0247, limit 0.05 | +0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it |  |
| sinucit_hud (frame 6016, tol 32; docs/fidelity.md item 3) | 0.0877 | measured 0.0877, limit 0.11 | -0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it | the weather mist's phase differs (difference 3, task 038) |
| sebenco_climb_hud (frame 6018, tol 32; docs/fidelity.md item 3) | 0.2993 | measured 0.2993, limit 0.32 | -0.0000 | faithful | faithful within 0.005 of the measured column, close up to the limit, differs above it | the weather mist's phase differs (difference 3, task 038) |

The Trajectories rows are task 046's `SCORECARD_RACE_CLOCK=ref/race_clock python3 tools/scorecard.py --only trajectories` (2026-10-07 13:43, commit 8a0d2da, 2m 28s): every port race read PPSSPP's race clock (`PURE_TEST_RACE_CLOCK`: the two `srand()` seeds the game takes from clock readings at the TEAM SELECTION confirm, the frame timer's answers, and the reference route's unlock state; files taken by `tools/ai_seed_check.sh`), so the AI ships race the reference's race (docs/fidelity.md difference 13). The notes' "another race, not noise" is task 044's wording for the runs without it. Task 044's --full run had 9 / 1 / 15 / 0 here: the players faithful on eight circuits (Sol 2 close at 3.25 m, Sinucit 13.89 m, Mandrashee 6.23 m and Karbonis 34.07 m differ) and every AI row differs from 0.38 to 0.45 s after GO (109 to 500 m). With the race clock all 12 players are faithful; the AI ships part 3 to 16 s after GO, where the VFPU's dot product rounds differently (difference 13, "What is left").

### Trajectories: differs (2026-10-07 13:43, commit 8a0d2da)

| Measure | Port | Reference | Difference | Grade | Threshold | Note |
|---|---|---|---|---|---|---|
| PPSSPP's AI ships: two runs of Vineta K at the same race clock | 1036 common samples | the same positions (under 0.01 m) | largest 0.000 m | faithful | deterministic when every common sample is under 0.01 m apart | the AI rows follow |
| Vineta K: the player, the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: never | PPSSPP, ref/scorecard/trajectories/vineta_k.csv (ae220eaad387) | 0.02 m at 17.25 s | faithful | faithful under 1.5 m, close under 5.0 m | 428 PPSSPP samples |
| Vineta K: the 7 AI ships (worst: ship 0), the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: 13.45 s | PPSSPP, ref/scorecard/trajectories/vineta_k.csv | 4.05 m at 16.00 s | close | faithful under 1.5 m, close under 5.0 m | 2996 PPSSPP samples; each side repeats its own AI from run to run (checked: PPSSPP on Vineta K, the port headless on Karbonis and Sinucit), so this is another race, not noise |
| Modesto Heights: the player, the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: never | PPSSPP, ref/scorecard/trajectories/modesto_heights.csv (677a50dcb5f4) | 0.09 m at 18.53 s | faithful | faithful under 1.5 m, close under 5.0 m | 415 PPSSPP samples |
| Modesto Heights: the 7 AI ships (worst: ship 5), the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: 10.94 s | PPSSPP, ref/scorecard/trajectories/modesto_heights.csv | 135.11 m at 14.31 s | **differs** | faithful under 1.5 m, close under 5.0 m | 2905 PPSSPP samples; each side repeats its own AI from run to run (checked: PPSSPP on Vineta K, the port headless on Karbonis and Sinucit), so this is another race, not noise |
| Chenghou Project: the player, the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: never | PPSSPP, ref/scorecard/trajectories/chenghou_project.csv (979c7cd6a6df) | 0.25 m at 14.20 s | faithful | faithful under 1.5 m, close under 5.0 m | 413 PPSSPP samples |
| Chenghou Project: the 7 AI ships (worst: ship 2), the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: 12.04 s | PPSSPP, ref/scorecard/trajectories/chenghou_project.csv | 103.47 m at 19.89 s | **differs** | faithful under 1.5 m, close under 5.0 m | 2891 PPSSPP samples; each side repeats its own AI from run to run (checked: PPSSPP on Vineta K, the port headless on Karbonis and Sinucit), so this is another race, not noise |
| Blue Ridge: the player, the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: never | PPSSPP, ref/scorecard/trajectories/blue_ridge.csv (1c543e7eb879) | 0.41 m at 19.99 s | faithful | faithful under 1.5 m, close under 5.0 m | 415 PPSSPP samples |
| Blue Ridge: the 7 AI ships (worst: ship 3), the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: 9.49 s | PPSSPP, ref/scorecard/trajectories/blue_ridge.csv | 140.13 m at 11.86 s | **differs** | faithful under 1.5 m, close under 5.0 m | 2905 PPSSPP samples; each side repeats its own AI from run to run (checked: PPSSPP on Vineta K, the port headless on Karbonis and Sinucit), so this is another race, not noise |
| Sinucit: the player, the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: never | PPSSPP, ref/scorecard/trajectories/sinucit.csv (be0a0f491e10) | 0.00 m at 10.71 s | faithful | faithful under 1.5 m, close under 5.0 m | 414 PPSSPP samples |
| Sinucit: the 7 AI ships (worst: ship 5), the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: 3.60 s | PPSSPP, ref/scorecard/trajectories/sinucit.csv | 280.70 m at 19.99 s | **differs** | faithful under 1.5 m, close under 5.0 m | 2898 PPSSPP samples; each side repeats its own AI from run to run (checked: PPSSPP on Vineta K, the port headless on Karbonis and Sinucit), so this is another race, not noise |
| Citta Nuova: the player, the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: never | PPSSPP, ref/scorecard/trajectories/citta_nuova.csv (0e5d2a9a3975) | 0.02 m at 17.18 s | faithful | faithful under 1.5 m, close under 5.0 m | 414 PPSSPP samples |
| Citta Nuova: the 7 AI ships (worst: ship 2), the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: 8.17 s | PPSSPP, ref/scorecard/trajectories/citta_nuova.csv | 83.86 m at 19.99 s | **differs** | faithful under 1.5 m, close under 5.0 m | 2898 PPSSPP samples; each side repeats its own AI from run to run (checked: PPSSPP on Vineta K, the port headless on Karbonis and Sinucit), so this is another race, not noise |
| Sebenco Climb: the player, the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: never | PPSSPP, ref/scorecard/trajectories/sebenco_climb.csv (e4fdb5faf052) | 0.03 m at 10.88 s | faithful | faithful under 1.5 m, close under 5.0 m | 420 PPSSPP samples |
| Sebenco Climb: the 7 AI ships (worst: ship 1), the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: 3.05 s | PPSSPP, ref/scorecard/trajectories/sebenco_climb.csv | 92.98 m at 19.95 s | **differs** | faithful under 1.5 m, close under 5.0 m | 2940 PPSSPP samples; each side repeats its own AI from run to run (checked: PPSSPP on Vineta K, the port headless on Karbonis and Sinucit), so this is another race, not noise |
| Sol 2: the player, the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: never | PPSSPP, ref/scorecard/trajectories/sol_2.csv (7054c81b613f) | 0.08 m at 18.92 s | faithful | faithful under 1.5 m, close under 5.0 m | 407 PPSSPP samples |
| Sol 2: the 7 AI ships (worst: ship 1), the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: 6.91 s | PPSSPP, ref/scorecard/trajectories/sol_2.csv | 423.60 m at 14.91 s | **differs** | faithful under 1.5 m, close under 5.0 m | 2849 PPSSPP samples; each side repeats its own AI from run to run (checked: PPSSPP on Vineta K, the port headless on Karbonis and Sinucit), so this is another race, not noise |
| Karbonis: the player, the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: never | PPSSPP, ref/scorecard/trajectories/karbonis.csv (2d35b4810fb3) | 0.00 m at 5.56 s | faithful | faithful under 1.5 m, close under 5.0 m | 423 PPSSPP samples |
| Karbonis: the 7 AI ships (worst: ship 4), the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: 9.56 s | PPSSPP, ref/scorecard/trajectories/karbonis.csv | 6.47 m at 19.39 s | **differs** | faithful under 1.5 m, close under 5.0 m | 2961 PPSSPP samples; each side repeats its own AI from run to run (checked: PPSSPP on Vineta K, the port headless on Karbonis and Sinucit), so this is another race, not noise |
| Sagarmatha: the player, the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: never | PPSSPP, ref/scorecard/trajectories/sagarmatha.csv (27ece46ff3a6) | 0.20 m at 17.17 s | faithful | faithful under 1.5 m, close under 5.0 m | 416 PPSSPP samples |
| Sagarmatha: the 7 AI ships (worst: ship 3), the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: 16.35 s | PPSSPP, ref/scorecard/trajectories/sagarmatha.csv | 6.19 m at 19.99 s | **differs** | faithful under 1.5 m, close under 5.0 m | 2912 PPSSPP samples; each side repeats its own AI from run to run (checked: PPSSPP on Vineta K, the port headless on Karbonis and Sinucit), so this is another race, not noise |
| Manor Top: the player, the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: never | PPSSPP, ref/scorecard/trajectories/manor_top.csv (0a95cb59c0c3) | 0.04 m at 17.00 s | faithful | faithful under 1.5 m, close under 5.0 m | 409 PPSSPP samples |
| Manor Top: the 7 AI ships (worst: ship 5), the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: 11.20 s | PPSSPP, ref/scorecard/trajectories/manor_top.csv | 52.35 m at 19.39 s | **differs** | faithful under 1.5 m, close under 5.0 m | 2863 PPSSPP samples; each side repeats its own AI from run to run (checked: PPSSPP on Vineta K, the port headless on Karbonis and Sinucit), so this is another race, not noise |
| Mandrashee: the player, the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: never | PPSSPP, ref/scorecard/trajectories/mandrashee.csv (8793afa5a20e) | 0.00 m at 10.33 s | faithful | faithful under 1.5 m, close under 5.0 m | 421 PPSSPP samples |
| Mandrashee: the 7 AI ships (worst: ship 5), the first clock more than 1 m apart; the largest distance over 20 s | first over 1 m: never | PPSSPP, ref/scorecard/trajectories/mandrashee.csv | 0.46 m at 13.21 s | faithful | faithful under 1.5 m, close under 5.0 m | 2947 PPSSPP samples; each side repeats its own AI from run to run (checked: PPSSPP on Vineta K, the port headless on Karbonis and Sinucit), so this is another race, not noise |

### Timing: faithful (2026-10-07 11:57, commit db10191)

| Measure | Port | Reference | Difference | Grade | Threshold | Note |
|---|---|---|---|---|---|---|
| Single Race: flips per race-clock second | 59.82 | 60 | -0.31% | faithful | faithful within 2% of the reference, close within 5% | 10582 flips over 176.9 s of race clock, this run's sweep cell single_race-vineta_k (PASS); the two-vblank stretches (the game's own) lower it by half their share |
| Tournament: flips per race-clock second | 59.36 | 60 | -1.07% | faithful | faithful within 2% of the reference, close within 5% | 88949 flips over 1498.5 s of race clock, the matrix's 3 Tournament cells at Vector (~/dev/pure-recomp/out/035-wip/fidelity, run 2026-10-06); the two-vblank stretches (the game's own) lower it by half their share |
| Time Trial: flips per race-clock second | 29.98 | 30 | -0.08% | faithful | faithful within 2% of the reference, close within 5% | 6448 flips over 215.1 s of race clock, this run's sweep cell time_trial-vineta_k (PASS) |
| Free Play: flips per race-clock second | 29.98 | 30 | -0.07% | faithful | faithful within 2% of the reference, close within 5% | 6348 flips over 211.8 s of race clock, this run's sweep cell free_play-vineta_k (PASS) |
| Zone: flips per race-clock second | 29.97 | 30 | -0.10% | faithful | faithful within 2% of the reference, close within 5% | 2010 flips over 67.1 s of race clock, this run's sweep cell zone-zone_1 (PASS) |
| two-vblank stretches over a follower-driven Vineta K race (its first 61 s, the race time both runs cover) | 1 (24 flips) | 0, ref/scorecard/timing/ppsspp/vineta_k/summary.json (7f993df372d7) | +1 | faithful | faithful when the counts differ by at most 1, close by at most 3 | port: this run's sweep cell single_race-vineta_k (PASS), 61 s of race; PPSSPP: PASS (laps 68.2, 62.6, 62.5 s, 43 contacts), 194 s of race; where they fall follows the weapons and the follower's put-backs, which differ run to run on both |
| the race load before Vineta K, in game time (TEAM SELECTION confirm to the race-start fade) | 0.30 s (to the race's first one-vblank flip 2.20 s) | 1.50 s (to the race's first one-vblank flip 3.40 s), ref/scorecard/timing/ppsspp/vineta_k/ppsspp.log (460d22982c1b) | -1.20 s | accepted (D-011) | difference 6, decided by Erik (D-011): the faster loads stay; reported, not graded | port flips from out/scorecard/runs/race-vineta_k.log |

### Audio: faithful (2026-10-07 11:57, commit db10191)

| Measure | Port | Reference | Difference | Grade | Threshold | Note |
|---|---|---|---|---|---|---|
| main menu music, 60 s from its start: --locate correlation (lowest of 3 two-second stretches) | 1.000 | PPSSPP's dump, ref/scorecard/audio/main_menu.wav (258049176cd1) | offset -56.55764 s (spread 0.0 ms) | faithful | faithful at or above 0.6, close at or above 0.3 (--locate, the same content) | the port's music from 145.48 s, PPSSPP's at 88.92 s; correlations 1.000, 1.000, 1.000 |
| main menu music, 60 s: mean per-second RMS ratio (port / PPSSPP) | 1.000 | 1 | +0.000 | faithful | faithful within 0.95 to 1.05, close within 0.9 to 1.1 | 60 s, per second 1.000 to 1.015 |
| Vineta K race: the port's music channel in PPSSPP's mix (median of 5 two-second stretches from GO + 10 s) | 0.627 | PPSSPP's dump, ref/scorecard/audio/vineta_k.wav (dd8d9af05935) | offset -77.85115 s (5 of 5 at it) | faithful | faithful at or above 0.6, close at or above 0.3 (--locate, the same content) | the effects are louder than the music in a race, and the AI's differ: 0.35, 0.57, 0.63, 0.74, 0.70 |
| Vineta K race: share of seconds where both mixes or neither are active (60 s from GO) | 1.00 | 1 | +0.00 | faithful | faithful at or above 98%, close at or above 90% | mean RMS ratio 0.982 (reported: the AI ships differ) |
| Vineta K race: clipped samples of the mix (60 s from GO) | 0 (0.000000) | 6 (0.000001) | -0.000001 | faithful | the port's clipped share at most PPSSPP's + 0.0001 faithful, + 0.001 close |  |
| Sinucit race: the port's music channel in PPSSPP's mix (median of 5 two-second stretches from GO + 10 s) | 0.689 | PPSSPP's dump, ref/scorecard/audio/sinucit.wav (b8340b36c9f3) | offset -69.35765 s (5 of 5 at it) | faithful | faithful at or above 0.6, close at or above 0.3 (--locate, the same content) | the effects are louder than the music in a race, and the AI's differ: 0.22, 0.42, 0.69, 0.74, 0.69 |
| Sinucit race: share of seconds where both mixes or neither are active (60 s from GO) | 1.00 | 1 | +0.00 | faithful | faithful at or above 98%, close at or above 90% | mean RMS ratio 0.993 (reported: the AI ships differ) |
| Sinucit race: clipped samples of the mix (60 s from GO) | 0 (0.000000) | 0 (0.000000) | +0.000000 | faithful | the port's clipped share at most PPSSPP's + 0.0001 faithful, + 0.001 close |  |
| Sagarmatha race: the port's music channel in PPSSPP's mix (median of 5 two-second stretches from GO + 10 s) | 0.735 | PPSSPP's dump, ref/scorecard/audio/sagarmatha.wav (afff66f58413) | offset -69.75972 s (5 of 5 at it) | faithful | faithful at or above 0.6, close at or above 0.3 (--locate, the same content) | the effects are louder than the music in a race, and the AI's differ: 0.40, 0.57, 0.78, 0.81, 0.74 |
| Sagarmatha race: share of seconds where both mixes or neither are active (60 s from GO) | 1.00 | 1 | +0.00 | faithful | faithful at or above 98%, close at or above 90% | mean RMS ratio 0.996 (reported: the AI ships differ) |
| Sagarmatha race: clipped samples of the mix (60 s from GO) | 0 (0.000000) | 0 (0.000000) | +0.000000 | faithful | the port's clipped share at most PPSSPP's + 0.0001 faithful, + 0.001 close |  |

### Saves: close (2026-10-07 11:57, commit db10191)

| Measure | Port | Reference | Difference | Grade | Threshold | Note |
|---|---|---|---|---|---|---|
| the save folder's files | ICON0.PNG, ICON1.PMF, PARAM.SFO, PIC1.PNG, PROFILE.BIN, SND0.AT3 | ICON0.PNG, ICON1.PMF, PARAM.SFO, PIC1.PNG, PROFILE.BIN, SND0.AT3 | the same | faithful | faithful when the same names, differs otherwise | PPSSPP: ref/scorecard/saves/UCUS98612P0000 |
| ICON0.PNG: size | 6742 bytes | 6742 bytes | +0 | faithful | faithful when the same size |  |
| ICON1.PMF: size | 51200 bytes | 51200 bytes | +0 | faithful | faithful when the same size |  |
| PARAM.SFO: size | 4912 bytes | 4912 bytes | +0 | faithful | faithful when the same size |  |
| PIC1.PNG: size | 172944 bytes | 172944 bytes | +0 | faithful | faithful when the same size |  |
| SND0.AT3: size | 97604 bytes | 97604 bytes | +0 | faithful | faithful when the same size |  |
| PROFILE.BIN (the data file): size | 41586 bytes | 41586 bytes | +0 | faithful | faithful when the same size | difference 5 (the PSP's savedata encryption, no-key mode): fixed by task 045, patch 0019 |
| PROFILE.BIN: the contents, decrypted by the framework's load path with both hashes checked | 41570 bytes (flag 0x01 (mode 1); PARAM.SFO hash (SAVEDATA_PARAMS) verified; PROFILE.BIN hash (SAVEDATA_FILE_LIST) verified, 41586 bytes; verdict PASS) | 41570 bytes | 71 bytes in 69 words, 69 of them user-RAM addresses on both sides | close | faithful when identical; close when the only differing words hold user-RAM addresses on both sides (the profile keeps heap pointers verbatim; the game sets them again on a load); differs otherwise | tools/save_interchange.sh --check (task 045) |
| PARAM.SFO TITLE | 'Wipeout Pure' | 'Wipeout Pure' | the same | faithful | faithful when equal |  |
| PARAM.SFO SAVEDATA_TITLE | 'Profile data' | 'Profile data' | the same | faithful | faithful when equal |  |
| PARAM.SFO SAVEDATA_DETAIL | 'User name: NAME0000  \nGold medals awarded: 0\nRanking: Rookie' | 'User name: NAME0000  \nGold medals awarded: 0\nRanking: Rookie' | the same | faithful | faithful when equal |  |
| PARAM.SFO CATEGORY | 'MS' | 'MS' | the same | faithful | faithful when equal |  |
| PARAM.SFO PARENTAL_LEVEL | 3 | 3 | the same | faithful | faithful when equal |  |
| PARAM.SFO SAVEDATA_FILE_LIST | 'PROFILE.BIN' | 'PROFILE.BIN' | the same | faithful | faithful when equal |  |
| ICON0.PNG, byte for byte | 78cdec5c2467 | 78cdec5c2467 | identical | faithful | faithful when identical, close when only the encoding differs |  |

### Coverage: close (2026-10-07 11:57, commit db10191)

| Measure | Port | Reference | Difference | Grade | Threshold | Note |
|---|---|---|---|---|---|---|
| the matrix's cells with a result | 46 (36 PASS, 10 STALL) | 46 | +0 | faithful | faithful when all 46 have a result and none is HALT, NO RACE, TIMEOUT or STUCK | ~/dev/pure-recomp/out/035-wip/fidelity/cells (the matrix of 2026-10-06, task 035); the stalls are the follower's (docs/fidelity.md) |
| halts (`Runtime stopped` other than the sweep's own) over the cells | 0 | 0 | +0 | faithful | faithful at 0, differs otherwise |  |
| stubs hit (`[hle-stub]`) over the cells | 0 | 0 | +0 | faithful | faithful at 0, differs otherwise |  |
| unsupported instructions over the cells | 0 | 0 | +0 | faithful | faithful at 0, differs otherwise |  |
| skipped draws (`[metal] ... not emulated` / `not implemented`) over the cells | 0 | 0 | +0 | faithful | faithful at 0, differs otherwise |  |
| imports implemented (a model of the call) | 249 of 278 | 278 | -29 | close | faithful when every implemented call the matrix made is checked against a game; close when one is answered from documentation only (UNVERIFIED) | called from documentation only: sceUtilityGetSystemParamString; config/imports.csv; the start-up list and the `[hle-stub]` and `UNVERIFIED` lines of the matrix's logs |
| imports stubbed with a documented value (the profile's constants) | 3: sceKernelRotateThreadReadyQueue, sceKernelGetThreadmanIdList, sceKernelGetGPI | 0 | +3 | close | faithful at 0; close when a constant stands in for the PSP's behaviour | GPI 0 as on retail; the ready-queue rotation a yield hint the scheduler covers; no thread ids (src/profile/pure_profile.cpp) |
| imports with no implementation: never called / called in the matrix | 26 never called, 0 called | 0 called | +0 called | faithful | faithful when none is called (a call prints `[hle-stub]`), differs otherwise | multiplayer, the download menu's network side, game sharing, the alarm and LoadExec calls |
| GE commands the framework still ignores (distinct, the exit list) | 30 | 0 | +30 | close | faithful at 0; close when every one left is one docs/fidelity.md found no draw of the game using; differs otherwise | this run's regress-main_menu+single_race (to the first race frame): REGION1, REGION2, ANTIALIASENABLE, PATCHCULLENABLE, LOGICOPENABLE, MORPHWEIGHT0, MORPHWEIGHT1, MORPHWEIGHT2, MORPHWEIGHT3, MORPHWEIGHT4, MORPHWEIGHT5, MORPHWEIGHT6, MORPHWEIGHT7, PATCHDIVISION, PATCHPRIMITIVE, PATCHFACING, SHADEMODE, TEXENVCOLOR, TEXSYNC, LOGICOP, UNKNOWNF0, UNKNOWNF1, UNKNOWNF2, UNKNOWNF3, UNKNOWNF4, UNKNOWNF5, UNKNOWNF6, UNKNOWNF7, UNKNOWNF8, UNKNOWNF9; the matrix's logs (before tasks 036, 037, 040): 65 |
| functions of config/function_map.csv entered during the matrix | - | - | - | not measured |  | no cheap entry count exists: PSPRECOMP_PROFILE_DISPATCH counts the outer dispatch loop only (chained calls never show) and slows the run, PSPRECOMP_COUNT_PC takes eight addresses; the VFPU differential test stays a task of its own (the brief's 045) |
