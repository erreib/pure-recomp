# The fidelity audit (task 035, 2026-10-06)

D-009 asks for the port as close to 1:1 with the original as possible before any enhancement. This audit measures
where it is not, across the campaign, and ends with the list the M8 fix tasks come from ("The differences", last
section). It changed no game-facing code: it ran the game, PPSSPP and the static analysis tools and compared.

Four kinds of evidence:

- **The campaign matrix** (`tools/fidelity_audit.py`, below): 46 cells headless on the Metal backend, every halt,
  unimplemented import, unemulated GE state, warning, two-vblank stretch and audio figure collected per cell.
- **PPSSPP references beyond the five**: new routes in `tools/ppsspp/routes/`, new captures in `ref/` (listed in
  `ref/README.md`), thirteen of them in the frame regression suite, and a PPSSPP race driven by the sweep's own
  follower (`tools/fidelity_audit.py --ppsspp-race`).
- **Audio** over every cell (`PURE_AUDIO_WAV` on each, `tools/wavstats.py` from the race start) and a five-minute
  idle on the main menu.
- **Saves and records** after a Single Race and a Tournament, a reboot that LOADs the autosaved profile, and two
  profiles in a row.

Plus the static analysis behind the two-vblank stretches (task 033's follow-up): Ghidra decompiles of the routines
that write the frame object's lock fields (the commands are under "The two-vblank stretches"). The decompiles, the GE
dump readers and the PPSSPP dumps of the Beta and Classic race frames named below were scratch files of the task's
first worktree and went with it; the commands here and in `ref/README.md` make them again.

## What matches

To read the list below in proportion, what the audit found the same as the original:

- **No halt anywhere.** No cell of the matrix printed `[hle-stub]`, `unsupported` or a `Runtime stopped` of its own;
  no `[metal] ... not emulated` or `not implemented` line appeared. The 26 imports without an implementation were
  never called.
- **The frontend, pixel for pixel.** Every menu compared (SINGLE PLAYER, CLASS, LEAGUE, TRACK and TEAM SELECTION,
  both 30-fps modes' TRACK SELECTION, TOURNAMENT SELECTION, Zone's TRACK SELECTION, OPTIONS, CONTROLS) differs from
  PPSSPP in 0 pixels at tol 24; the HUD (labels, digits, bars) matches on every track's first race frame; the pause
  menu, the results panel and Zone's end panel have PPSSPP's layout and fonts.
- **The game's logic and timing.** The same follower drove Vineta K in PPSSPP and in the port to laps within 1.5 s
  of each other and the same 45 contacts; Zone 1 with Cross held ends in both at TOTAL ZONES CLEAR 6, TOP SPEED
  405.07 (PPSSPP) and 404.68 (port), SCORE 4292 and 4291, and the end panels differ in 1.8% of the pixels; the race
  start runs the same 57 frames at two vblanks; the two-vblank stretches are the game's own and PPSSPP has them too
  (below).
- **Saves round-trip.** The autosaves after a Single Race and after the tournament's races write the profile, and a
  reboot that LOADs it shows the records the races set and the play times.
- **Audio keeps going.** Every race has its mix, its music and its effects active in every second from the start,
  with clipping in at most 0.014% of the samples, the only gaps being the game's own between music tracks (below).
- **Every circuit reachable.** All 12 circuits race in Single Race at Vector and Phantom and in Time Trial, Free Play
  on each league, the tournaments and the four Zone tracks; where the follower fails (Sinucit's fork, Manor Top's
  bend, a wedge on Chenghou Project) the game itself behaves.

## The campaign matrix (item 2)

```
python3 tools/fidelity_audit.py [--cells FILE] [--resume]     # the 46 cells, one at a time, about 4 h
python3 tools/fidelity_audit.py --report                      # the tables again from out/fidelity/cells/*.json
```

Every cell is `tools/campaign_sweep.py MODE TRACK --no-damage [--class phantom]` from a cold boot on an empty memory
stick, headless on the Metal backend, the race paced, with `PURE_AUDIO_WAV`; `(extended)` cells are the league
picks the sweep's tables lack, added by the audit in the sweep's process (README.md). The table is in the brief's
order; the run of 2026-10-06 went in that of `out/fidelity/order.txt` (four cells that tried the extended routes and
Phantom first, then the rest). The three cells of `--quick` (Single Race Vineta K, Zone 1, Time Trial Vineta K) are
those of the Verify. Columns: the sweep's outcome
and the flip it ended at, laps, the race clock and the wall time; the tracks whose `TrackStartup.xml` the race load
opened (the proof that the route picked the track); halts and stubs, then other warning lines; how many distinct GE
commands the framework ignored; the two-vblank stretches and hitches; the lowest of the Metal backend's per-600-frame
rates in the race; the render pipelines a draw made that the pre-warm list lacks; the audio; the savedata requests
beyond the two every boot makes; the sweep's detail.

| cell | outcome | flip | laps | race s | wall s | track loaded | halts, stubs, warnings | GE ignored | stretches; hitches | min fps | pipelines not listed | audio mix / music / clip | saves | detail |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| single_race-vineta_k | PASS | 17950 | 3 | 196.1 | 205 | 01_Vineta_K | 0, 2 | 65 | 3 (2.1 s) | 57.3 | 0 | 1.00 / 1.00 / 0.0000 | - | results screen at flip 17940 (3 laps: 66.7, 59.6, 59.9 s; 196.0 s at the shot); 45 contacts (16, 13, 16 a lap); 89 shield taken and refilled (no da... |
| single_race-modesto_heights | PASS | 23310 | 3 | 286.2 | 295 | 03_Modesto_Heights | 0, 2 | 65 | 5 (3.5 s) | 56.5 | 0 | 1.00 / 1.00 / 0.0000 | - | results screen at flip 23300 (3 laps: 89.6, 100.5, 91.3 s; 286.1 s at the shot); 79 contacts (24, 25, 30 a lap); 157 shield taken and refilled (no ... |
| single_race-chenghou_project | STALL | 15730 | 1 | 160.5 | 169 | 04_Chenghou_Project | 0, 2 | 65 | 6 (5.0 s) | 56.4 | 0 | 1.00 / 1.00 / 0.0000 | - | stopped (no contact since the last progress; crawling at 368 km/h with Cross held; shield bar 100%); no progress for 20.0 s of race clock; 41 conta... |
| single_race-blue_ridge | PASS | 22130 | 3 | 268.4 | 277 | 07_Blue_Ridge | 0, 4 | 65 | 8 (7.3 s); 1 hitch (longest 132 ms) | 55.6 | 0 | 1.00 / 1.00 / 0.0001 | - | results screen at flip 22120 (3 laps: 84.3, 90.8, 89.1 s; 268.2 s at the shot); 73 contacts (22, 26, 25 a lap); 141 shield taken and refilled (no d... |
| single_race-sinucit | STALL | 16080 | 1 | 169.4 | 178 | 08_Sinucit | 0, 2 | 65 | 11 (11.2 s) | 53.8 | 0 | 1.00 / 1.00 / 0.0000 | - | put back by the game 5 times since the last progress (it left the track at 948, 908, 943, 944, 944 m and was set down at about 518 m; crawling at 3... |
| single_race-citta_nuova | PASS | 25930 | 3 | 330.3 | 340 | 09_Citta_Nuova_V | 0, 3 | 65 | 6 (4.4 s) | 57.0 | 0 | 1.00 / 0.98 / 0.0001 | - | results screen at flip 25920 (3 laps: 107.9, 111.9, 106.3 s; 330.2 s at the shot); 100 contacts (29, 35, 36 a lap); 233 shield taken and refilled (... |
| single_race-sebenco_climb | PASS | 26430 | 3 | 337.1 | 346 | 10_Sebenco_Climb | 0, 3 | 65 | 2 (1.0 s) | 58.5 | 0 | 1.00 / 0.98 / 0.0000 | - | results screen at flip 26420 (3 laps: 105.6, 103.0, 124.3 s; 336.9 s at the shot); 94 contacts (30, 28, 36 a lap); 180 shield taken and refilled (n... |
| single_race-sol_2 | PASS | 21340 | 3 | 251.9 | 261 | 12_Sol_2 | 0, 2 | 65 | 1 (0.5 s) | 58.5 | 0 | 1.00 / 1.00 / 0.0000 | - | results screen at flip 21330 (3 laps: 86.2, 83.8, 76.1 s; 251.7 s at the shot); 65 contacts (24, 22, 19 a lap); 131 shield taken and refilled (no d... |
| single_race-karbonis | PASS | 20750 | 3 | 246.2 | 255 | 01_Karbonis | 0, 2 | 65 | 10 (8.9 s) | 54.5 | 0 | 1.00 / 1.00 / 0.0000 | - | results screen at flip 20740 (3 laps: 81.5, 71.1, 86.8 s; 246.0 s at the shot); 73 contacts (23, 24, 26 a lap); 164 shield taken and refilled (no d... |
| single_race-sagarmatha | PASS | 19450 | 3 | 221.7 | 230 | 02_Sagarmartha | 0, 6 | 65 | 3 (3.1 s); 2 hitches (longest 132 ms) | 53.7 | 0 | 1.00 / 1.00 / 0.0000 | - | results screen at flip 19440 (3 laps: 71.0, 75.3, 68.6 s; 221.6 s at the shot); 49 contacts (16, 15, 18 a lap); 101 shield taken and refilled (no d... |
| single_race-manor_top | STALL | 11350 | 0 | 90.2 | 98 | 03_Manor_Top | 0, 2 | 65 | 10 (10.7 s) | 52.0 | 0 | 1.00 / 1.00 / 0.0000 | - | put back by the game 5 times since the last progress (it left the track at 2473, 2235, 2395, 2389, 2397 m and was set down at about 2036 m; crawlin... |
| single_race-mandrashee | PASS | 21370 | 3 | 253.3 | 262 | 04_Mandrashee | 0, 5 | 65 | 2 (2.2 s); 1 hitch (longest 295 ms) | 57.1 | 0 | 1.00 / 1.00 / 0.0000 | - | results screen at flip 21360 (3 laps: 99.5, 77.5, 69.0 s; 253.1 s at the shot); 73 contacts (31, 24, 18 a lap); 157 shield taken and refilled (no d... |
| single_race-vineta_k-phantom | PASS | 26220 | 5 | 339.2 | 348 | 01_Vineta_K | 0, 3 | 65 | 14 (12.6 s) | 51.9 | 0 | 1.00 / 0.98 / 0.0000 | - | results screen at flip 26210 (5 laps: 68.8, 61.0, 62.7, 74.6, 64.8 s; 339.0 s at the shot); 130 contacts (26, 21, 25, 32, 26 a lap); 475 shield tak... |
| single_race-modesto_heights-phantom | PASS | 33920 | 5 | 471.2 | 480 | 03_Modesto_Heights | 0, 3 | 65 | 22 (19.8 s) | 49.4 | 0 | 1.00 / 0.99 / 0.0000 | - | results screen at flip 33910 (5 laps: 116.5, 92.0, 81.6, 88.2, 86.5 s; 471.1 s at the shot); 177 contacts (43, 32, 36, 29, 37 a lap); 637 shield ta... |
| single_race-chenghou_project-phantom | PASS | 32710 | 5 | 461.6 | 470 | 04_Chenghou_Project | 0, 3 | 65 | 40 (41.7 s) | 48.2 | 0 | 1.00 / 0.98 / 0.0000 | - | results screen at flip 32700 (5 laps: 77.8, 94.7, 125.1, 86.5, 73.2 s; 461.4 s at the shot); 183 contacts (28, 41, 48, 37, 29 a lap); 760 shield ta... |
| single_race-blue_ridge-phantom | PASS | 32840 | 5 | 445.3 | 454 | 07_Blue_Ridge | 0, 3 | 65 | 6 (3.8 s) | 57.2 | 0 | 1.00 / 0.98 / 0.0000 | - | results screen at flip 32830 (5 laps: 105.0, 91.8, 82.8, 88.9, 73.0 s; 445.2 s at the shot); 160 contacts (36, 36, 27, 34, 27 a lap); 531 shield ta... |
| single_race-sinucit-phantom | STALL | 9070 | 0 | 53.5 | 62 | 08_Sinucit | 0, 2 | 65 | 13 (13.4 s) | 50.0 | 0 | 1.00 / 1.00 / 0.0000 | - | put back by the game 8 times since the last progress (it left the track at 956, 970, 932, 949, 925, 939, 949, 960 m and was set down at about 514 m... |
| single_race-citta_nuova-phantom | PASS | 41680 | 5 | 596.8 | 606 | 09_Citta_Nuova_V | 0, 6 | 65 | 17 (12.0 s); 1 hitch (longest 102 ms) | 53.2 | 0 | 1.00 / 0.98 / 0.0001 | - | results screen at flip 41670 (5 laps: 103.7, 108.4, 142.0, 113.3, 124.7 s; 596.6 s at the shot); 213 contacts (35, 45, 51, 39, 43 a lap); 779 shiel... |
| single_race-sebenco_climb-phantom | PASS | 33820 | 5 | 463.0 | 472 | 10_Sebenco_Climb | 0, 5 | 65 | 6 (6.5 s); 1 hitch (longest 110 ms) | 54.8 | 0 | 1.00 / 0.98 / 0.0000 | - | results screen at flip 33810 (5 laps: 97.5, 95.1, 87.1, 79.5, 99.7 s; 462.9 s at the shot); 162 contacts (35, 31, 25, 32, 39 a lap); 549 shield tak... |
| single_race-sol_2-phantom | PASS | 30150 | 5 | 408.2 | 417 | 12_Sol_2 | 0, 5 | 65 | 19 (19.7 s); 1 hitch (longest 108 ms) | 48.0 | 0 | 1.00 / 0.98 / 0.0000 | - | results screen at flip 30140 (5 laps: 88.7, 96.3, 78.5, 73.2, 67.4 s; 408.1 s at the shot); 160 contacts (33, 37, 32, 30, 28 a lap); 611 shield tak... |
| single_race-karbonis-phantom | STALL | 13770 | 1 | 133.5 | 141 | 01_Karbonis | 0, 2 | 65 | 16 (16.7 s) | 44.9 | 0 | 1.00 / 1.00 / 0.0000 | - | put back by the game 6 times since the last progress (it left the track at 2982, 2951, 2928, 2954, 2875, 2972 m and was set down at about 2395 m; c... |
| single_race-sagarmatha-phantom | PASS | 27060 | 5 | 349.3 | 357 | 02_Sagarmartha | 0, 3 | 65 | 4 (4.6 s) | 51.7 | 0 | 1.00 / 0.98 / 0.0000 | - | results screen at flip 27050 (5 laps: 77.4, 70.7, 71.7, 59.6, 66.2 s; 349.2 s at the shot); 121 contacts (30, 24, 27, 18, 22 a lap); 416 shield tak... |
| single_race-manor_top-phantom | STALL | 17400 | 1 | 197.2 | 205 | 03_Manor_Top | 0, 2 | 65 | 23 (23.2 s) | 48.9 | 0 | 1.00 / 1.00 / 0.0000 | - | put back by the game 5 times since the last progress (it left the track at 2519, 2250, 2196, 2252, 2230 m and was set down at about 2065 m; crawlin... |
| single_race-mandrashee-phantom | PASS | 24640 | 5 | 311.4 | 321 | 04_Mandrashee | 0, 2 | 65 | 9 (9.6 s) | 51.2 | 0 | 1.00 / 1.00 / 0.0000 | - | results screen at flip 24630 (5 laps: 60.8, 62.0, 52.4, 60.5, 68.9 s; 311.2 s at the shot); 119 contacts (25, 25, 20, 25, 24 a lap); 445 shield tak... |
| time_trial-vineta_k | PASS | 12390 | 3 | 212.9 | 221 | 01_Vineta_K | 0, 2 | 65 | 0 | 30.0 | 3 | 1.00 / 1.00 / 0.0000 | - | results screen at flip 12380 (3 laps: 72.3, 67.2, 67.9 s; 212.6 s at the shot); 59 contacts (18, 21, 20 a lap); 64 shield taken and refilled (no da... |
| time_trial-modesto_heights | PASS | 16430 | 3 | 347.7 | 356 | 03_Modesto_Heights | 0, 7 | 65 | 0; 2 hitches (longest 133 ms) | 29.7 | 3 | 1.00 / 0.98 / 0.0000 | - | results screen at flip 16420 (3 laps: 112.7, 106.4, 124.5 s; 347.4 s at the shot); 111 contacts (35, 35, 41 a lap); 111 shield taken and refilled (... |
| time_trial-chenghou_project | PASS | 15150 | 3 | 305.0 | 313 | 04_Chenghou_Project | 0, 4 | 65 | 0; 1 hitch (longest 117 ms) | 29.7 | 2 | 1.00 / 1.00 / 0.0000 | - | results screen at flip 15140 (3 laps: 98.8, 103.8, 98.0 s; 304.7 s at the shot); 100 contacts (31, 34, 35 a lap); 84 shield taken and refilled (no ... |
| time_trial-blue_ridge | PASS | 15610 | 3 | 320.3 | 329 | 07_Blue_Ridge | 0, 2 | 65 | 0 | 30.0 | 3 | 1.00 / 1.00 / 0.0000 | - | results screen at flip 15600 (3 laps: 94.3, 114.7, 107.3 s; 320.0 s at the shot); 100 contacts (30, 38, 32 a lap); 100 shield taken and refilled (n... |
| time_trial-sinucit | STALL (extended) | 7270 | 0 | 42.0 | 50 | 08_Sinucit | 0, 2 | 65 | 0 | 30.0 | 0 | 1.00 / 1.00 / 0.0000 | - | put back by the game 4 times since the last progress (it left the track at 976, 941, 926, 835 m and was set down at about 507 m; crawling at 283 km... |
| time_trial-citta_nuova | PASS (extended) | 18350 | 3 | 411.7 | 420 | 09_Citta_Nuova_V | 0, 3 | 65 | 0 | 29.8 | 3 | 1.00 / 0.98 / 0.0000 | - | results screen at flip 18340 (3 laps: 137.1, 147.1, 121.3 s; 411.4 s at the shot); 131 contacts (46, 47, 38 a lap); 131 shield taken and refilled (... |
| time_trial-sebenco_climb | PASS (extended) | 19110 | 3 | 437.0 | 446 | 10_Sebenco_Climb | 0, 3 | 65 | 0 | 29.8 | 3 | 1.00 / 0.98 / 0.0000 | - | results screen at flip 19100 (3 laps: 167.0, 147.5, 117.6 s; 436.7 s at the shot); 153 contacts (58, 52, 43 a lap); 146 shield taken and refilled (... |
| time_trial-sol_2 | PASS (extended) | 15960 | 3 | 331.9 | 340 | 12_Sol_2 | 0, 3 | 65 | 0 | 29.8 | 3 | 1.00 / 0.98 / 0.0000 | - | results screen at flip 15950 (3 laps: 104.3, 116.9, 105.9 s; 331.6 s at the shot); 105 contacts (35, 38, 32 a lap); 117 shield taken and refilled (... |
| time_trial-karbonis | PASS (extended) | 13180 | 3 | 239.2 | 247 | 01_Karbonis | 0, 2 | 65 | 0 | 29.8 | 3 | 1.00 / 1.00 / 0.0000 | - | results screen at flip 13170 (3 laps: 81.5, 73.2, 78.1 s; 238.9 s at the shot); 73 contacts (26, 21, 26 a lap); 79 shield taken and refilled (no da... |
| time_trial-sagarmatha | PASS (extended) | 13660 | 3 | 255.3 | 263 | 02_Sagarmartha | 0, 2 | 65 | 0 | 30.0 | 3 | 1.00 / 1.00 / 0.0000 | - | results screen at flip 13650 (3 laps: 70.5, 82.2, 94.9 s; 255.0 s at the shot); 78 contacts (24, 26, 28 a lap); 69 shield taken and refilled (no da... |
| time_trial-manor_top | STALL (extended) | 8890 | 0 | 96.1 | 104 | 03_Manor_Top | 0, 2 | 65 | 0 | 30.0 | 0 | 1.00 / 1.00 / 0.0000 | - | put back by the game 6 times since the last progress (it left the track at 2615, 2215, 2311, 2305, 2251, 2450 m and was set down at about 2068 m; c... |
| time_trial-mandrashee | PASS (extended) | 14610 | 3 | 286.9 | 295 | 04_Mandrashee | 0, 2 | 65 | 0 | 29.8 | 3 | 1.00 / 1.00 / 0.0000 | - | results screen at flip 14600 (3 laps: 88.9, 90.5, 101.3 s; 286.6 s at the shot); 102 contacts (34, 33, 35 a lap); 101 shield taken and refilled (no... |
| free_play-vineta_k | PASS | 12630 | 3 | 216.9 | 230 | 01_Vineta_K | 0, 6 | 65 | 0; 2 hitches (longest 133 ms) | 29.6 | 3 | 1.00 / 0.99 / 0.0000 | - | results screen at flip 12620 (3 laps: 74.2, 71.2, 67.4 s; 216.6 s at the shot); 59 contacts (21, 20, 18 a lap); 61 shield taken and refilled (no da... |
| free_play-sol_2 | PASS (extended) | 15650 | 3 | 317.7 | 330 | 12_Sol_2 | 0, 4 | 65 | 0; 1 hitch (longest 133 ms) | 29.8 | 3 | 1.00 / 0.99 / 0.0000 | - | results screen at flip 15640 (3 laps: 99.3, 98.9, 114.1 s; 317.4 s at the shot); 88 contacts (31, 26, 31 a lap); 110 shield taken and refilled (no ... |
| free_play-karbonis | PASS (extended) | 14130 | 3 | 266.9 | 279 | 01_Karbonis | 0, 2 | 65 | 0 | 30.0 | 3 | 1.00 / 0.99 / 0.0000 | - | results screen at flip 14120 (3 laps: 110.7, 72.4, 79.5 s; 266.6 s at the shot); 88 contacts (34, 26, 28 a lap); 97 shield taken and refilled (no d... |
| tournament-alpha | PASS | 70140 | 12 | 1001.2 | 1104 | 01_Vineta_K,03_Modesto_Heights,04_Chenghou_Project,07_Blue_Ridge | 0, 5 | 65 | 17 (15.2 s) | 39.7 | 3 | 1.00 / 0.98 / 0.0000 | AUTOSAVE UCUS98612P0000/PROFILE.BIN x3 | final standings (TOURNAMENT STANDING after race 4) at flip 70130; race 1 vineta_k: 3 laps: 64.6, 59.1, 59.9 s, 43 contacts (14, 17, 12 a lap); 80 s... |
| tournament-beta | STALL (extended) | 8300 | 0 | 40.2 | 49 | 08_Sinucit | 0, 2 | 65 | 6 (5.7 s) | 54.6 | 0 | 1.00 / 1.00 / 0.0000 | - | put back by the game 4 times since the last progress (it left the track at 970, 962, 938, 950 m and was set down at about 485 m; crawling at 270 km... |
| tournament-classic | STALL (extended) | 37780 | 6 | 491.0 | 554 | 01_Karbonis,02_Sagarmartha,03_Manor_Top | 0, 5 | 65 | 11 (9.0 s); 1 hitch (longest 110 ms) | 39.8 | 3 | 1.00 / 0.97 / 0.0000 | AUTOSAVE UCUS98612P0000/PROFILE.BIN x2 | put back by the game 4 times since the last progress (it left the track at 1733, 1723, 1532, 1526 m and was set down at about 1332 m; crawling at 1... |
| zone-zone_1 | PASS | 7390 | 0 | 67.1 | 75 | 01_Zone | 0, 2 | 65 | 0 | 30.0 | 0 | 1.00 / 1.00 / 0.0000 | - | zone end panel at flip 7380: TOTAL ZONES CLEAR 6; destroyed at flip 7153 (59.2 s of race clock, 279 m), 0 laps; 1 contacts (1 a lap); shield -0.1 a... |
| zone-zone_2 | PASS | 7410 | 0 | 67.7 | 76 | 02_Zone | 0, 2 | 65 | 0 | 30.0 | 0 | 1.00 / 1.00 / 0.0000 | - | zone end panel at flip 7400: TOTAL ZONES CLEAR 7; destroyed at flip 7171 (59.8 s of race clock, 443 m), 0 laps; 1 contacts (1 a lap); shield -0.1 a... |
| zone-zone_3 | PASS | 7490 | 0 | 70.4 | 78 | 03_Zone | 0, 2 | 65 | 0 | 30.0 | 0 | 1.00 / 1.00 / 0.0000 | - | zone end panel at flip 7480: TOTAL ZONES CLEAR 7; destroyed at flip 7254 (62.5 s of race clock, 1815 m), 0 laps; 6 contacts (6 a lap); shield -0.1 ... |
| zone-zone_4 | PASS | 7450 | 0 | 69.1 | 77 | 04_Zone | 0, 4 | 65 | 0; 1 hitch (longest 117 ms) | 30.0 | 0 | 1.00 / 1.00 / 0.0000 | - | zone end panel at flip 7440: TOTAL ZONES CLEAR 7; destroyed at flip 7210 (61.1 s of race clock, 1606 m), 0 laps; 3 contacts (3 a lap); shield -0.0 ... |

**All 46 cells ran** (2026-10-06, 19:20 to 23:06; 3.75 h of wall time for 3.6 h of race clock, under the brief's six
hours): **36 PASS, 10 STALL**, no HALT, NO RACE, TIMEOUT or STUCK. `tools/fidelity_audit.py --resume` on the finished
matrix runs nothing and ends with `46 of 46 cells have a result (36 PASS, 10 STALL); complete`. Every cell's race load
opened the `TrackStartup.xml` of the track it meant, the extended cells included, so the league picks the audit adds
to the sweep hold. By mode:

| Mode | Cells | PASS | STALL | Notes |
|---|---|---|---|---|
| Single Race, Vector | 12 | 9 | 3 | Chenghou Project, Sinucit, Manor Top |
| Single Race, Phantom | 12 | 9 | 3 | Sinucit, Karbonis, Manor Top (Chenghou Project finishes at Phantom) |
| Time Trial, Vector | 12 | 10 | 2 | Sinucit, Manor Top (both extended) |
| Free Play, Vector | 3 | 3 | 0 | Vineta K, Sol 2, Karbonis |
| Tournament, Vector | 3 | 1 | 2 | Alpha complete (four races, final standings); Beta stops in race 1 (Sinucit); Classic in race 3 (Manor Top), after two races and two autosaves |
| Zone | 4 | 4 | 0 | TOTAL ZONES CLEAR 6, 7, 7, 7 with Cross held |

The ten stalls are the follower's, at four places, and in each the game behaves (the sweep's detail says what the ship
did; each cell ran once and was not retried, as the brief asks):

- **Sinucit's fork** (four cells: Single Race at Vector and Phantom, Time Trial, race 1 of the Beta tournament): the
  ship leaves the track at 835 to 976 m and the game sets it down at 485 to 520 m, four to eight times, until the
  sweep's 20 s without progress. Because Sinucit is the Beta tournament's first race, Citta Nuova, Sebenco Climb and
  Sol 2 were raced in Single Race and Time Trial only (and Sol 2 in Free Play).
- **Manor Top** (Single Race at Vector and Phantom, Time Trial: the bend at 2196 to 2615 m, set down at 2036 to 2068
  m, five or six times; race 3 of the Classic tournament, earlier on the lap: off at 1526 to 1733 m, set down at about
  1332 m, four times).
- **Karbonis at Phantom**: off at 2875 to 2982 m, set down at about 2395 m, six times (at Vector it finishes).
- **Chenghou Project at Vector**, lap 2: wedged against a wall at about 4149 m with no contact, crawling with Cross
  held (at Phantom it finishes five laps).

The other columns, over the whole matrix:

- **Halts, stubs, warnings**: no halt and no stub anywhere; the warnings counted are the audio capture's underrun
  lines, two in every cell and up to seven in one (the next section says what they are).
- **GE ignored**: the framework lists the same 65 GE commands it does not apply in every cell (next section).
- **Min fps**: the lowest Metal rate over a 600-frame window of the race is 44.9 to 58.5 in the 60-fps modes, pulled
  down by the two-vblank stretches, and 29.6 to 30.0 in Time Trial, Free Play and Zone, which run at 30 throughout;
  the tournaments' 39.7 is a window that holds a 30-fps standings screen.
- **Pipelines not listed**: three render pipelines that `config/metal_pipelines.txt` (the pre-warm list of task 033)
  lacks are made by a draw in every Time Trial and Free Play cell that reached its results screen (two on Chenghou
  Project) and in the tournaments that got past race 1; never in a Single Race, a Zone cell or a stalled Time Trial.
  So they come with the 30-fps modes' result and standings screens. The logs do not say when (a `PURE_METAL_TRACE`
  run would): a candidate for the pre-warm list rather than a known difference.
- **Stretches; hitches**: the two-vblank stretches (290 in the 60-fps cells, 273 s in all) are item 6's subject,
  below. A hitch is a race flip 45 ms or more after the one before: 12 cells have one or two, 102 to 295 ms, at no
  fixed place (next section, and difference 7).
- **Audio**: the mix is active in every second of every race; the music channel in 97 to 100% of the seconds (the
  audio section).
- **Saves**: beyond the two requests every boot makes, only the tournaments save (an AUTOSAVE of
  `UCUS98612P0000/PROFILE.BIN` after each race but the last); a Single Race cell quits at its results panel, before
  the game saves (the saves section ran one past it).

## Halts, stubs and what the GE draws without (item 1's feature table)

`out/fidelity/features.md` lists every distinct line the collectors took from the cells' logs (frame numbers and
times taken out), then the framework's exit list of GE commands it ignores, then the imports with no
implementation. Over the whole matrix:

| line | cells | count | first cell |
|---|---|---|---|
| `[pure] audio capture: channel 3 underrun (the game handed sceAudio a buffer late)` | 46 | 92 | single_race-vineta_k |
| `[pure] audio capture: channel 2 underrun (the game handed sceAudio a buffer late)` | 23 | 34 | single_race-blue_ridge |
| `[pure] audio capture: channel 1 underrun (the game handed sceAudio a buffer late)` | 12 | 16 | single_race-blue_ridge |

No cell printed a `[hle-stub]` line, an `unsupported` line, a `Runtime stopped` of its own, a `[metal] ... is not
emulated` or `not implemented` line, or a warning of `[render]`, `[mpeg]`, `[atrac]`, `[sas]`, `[psmfplayer]`,
`[savedata]` or `[audio]`, and the game's own `[guest]` output has no error, failure, assertion or warning line. The
only lines the collectors kept are the audio capture's own (`PURE_AUDIO_WAV`: it says when the game handed sceAudio a
channel's buffer late, and how long the channel went without):

- **Channel 3 (the movies')**, twice in every cell, at 28.3 and 33.2 s of virtual time, 1947 and 1931 ms, the same
  to the frame in all 46: after the language screen, between the parts of the intro, while the game keeps its movie
  channel reserved and sends it nothing. A reserved channel with no data plays nothing on a PSP either, so this is the
  capture's bookkeeping, not a difference.
- **Channel 1 (sceSas: the effects and engines)**, 16 lines in 12 cells: every one at a **hitch**, a race flip 102 to
  295 ms after the one before (the matrix's hitches column), with a channel 2 line at the same moment. Nothing else is
  in the log there (no file opened, no save, no load): the virtual clock jumps in one flip and the game's race clock
  moves by its per-frame cap (in Mandrashee 0.067 s for a 295 ms flip). That is what a paced run does when its
  process is held up for a moment: the kernel's clock catches up with real time at once. Two of these cells run again
  at 23:35 (Zone 4 and Free Play Vineta K, `out/fidelity-hitch/`) had hitches again, at other places (117 ms; 117 and
  167 ms), so they are not tied to a place in the game. Neither run had an idle machine (the audit's PPSSPP captures
  and Ghidra decompiles until 21:51; a browser, Spotlight indexing and other sessions' work, a load average of about
  5, at the rerun), and the sweep reads the game's output through a pty while it steers, so a reader held up for a
  moment holds the game's writes. Whether a player's run has them is open: difference 7.
- **Channel 2 (the music)**, 34 lines in 23 cells: the hitches above, and once at each change of music track, 15 to
  60 ms just after the new track starts: at 527.3 s of virtual time in every cell that runs that long (the first
  change, 5:24 into the race music), and at the later changes of the long cells (636, 755, 932 and 1224 s). Each
  follows a silence on the music channel (the audio section): difference 8.

The framework's list of ignored GE commands, summed over the cells (every cell lists the same 65):

| Feature | Commands (GE opcodes) | Writes over the 46 cells | A cell, mean |
|---|---|---|---|
| mipmaps | TEXADDR1 to 7 (0xA1 to 0xA7), TEXBUFWIDTH1 to 7 (0xA9 to 0xAF), TEXSIZE1 to 7 (0xB9 to 0xBF), TEXLEVEL (0xC8), TEXLODSLOPE (0xD0) | 1,042,018,386 | 22,652,574 |
| the colour test | COLORTESTENABLE (0x27), COLORTEST (0xD8), COLORREF (0xD9), COLORTESTMASK (0xDA) | 353,381,746 | 7,682,212 |
| drawing region | REGION1, REGION2 (0x15, 0x16) | 55,421,772 | 1,204,821 |
| environment and projection mapping | TEXMAPMODE (0xC0), TEXSHADELS (0xC1) | 25,481,939 | 553,955 |
| dithering | DITHERENABLE (0x20), DITH1 to 4 (0xE2 to 0xE5) | 3,801,149 | 82,634 |
| texture cache sync | TEXSYNC (0xCC) | 3,781,510 | 82,207 |
| depth clamp | CLIPENABLE (0x1C) | 917,984 | 19,956 |
| logic ops | LOGICOPENABLE (0x28), LOGICOP (0xE6) | 128,849 | 2,801 |
| undocumented (the GE init) | 0xF0 to 0xF9 | 460 | 10 |
| vertex morphing | MORPHWEIGHT0 to 7 (0x2C to 0x33) | 368 | 8 |
| Bezier and spline patches | PATCHCULLENABLE (0x26), PATCHDIVISION (0x36), PATCHPRIMITIVE (0x37), PATCHFACING (0x38) | 230 | 5 |
| the blend texture function's colour | TEXENVCOLOR (0xCA) | 92 | 2 |
| flat shading | SHADEMODE (0x50) | 92 | 2 |
| anti-aliasing (no effect on a PSP) | ANTIALIASENABLE (0x25) | 46 | 1 |

All 65 are in every cell's list, and every cell saw the reset value 0 first for each. `out/fidelity/features.md` has
them one by one.

### The GE state the framework ignores, and how much of it the game uses

The framework's GE state (`vendor/portablekit/host/gpu/ge_state.cpp`) counts every GE command it does not apply and
prints the list at exit (`GE commands ignored: 65 distinct`, the count and the first value of each); the Metal
backend draws from that state, so these never reach a picture. The counts tell how often the game writes a command,
not whether it changes anything: the first value is the reset value in every cell. Whether the game turns a feature
on was read from PPSSPP's GE dumps, which hold the complete state of every draw (a reader on top of
`tools/ppsspp/ppdmp.py` that replays each dump's state draw by draw; draws of the frame, clears left out):

| PPSSPP dump (the first full-HUD frame of each race, the TEAM screen) | draws | textured | with mip levels | environment map (TEXMAPMODE 2) | texture matrix (TEXMAPMODE 1) | colour test | dither | depth clamp | fogged |
|---|---|---|---|---|---|---|---|---|---|
| Vineta K | 866 | 845 | 621 | 96 | 40 | 6 | 60 | 860 | 558 |
| Modesto Heights | 806 | 787 | 656 | 81 | 0 | 11 | 58 | 800 | 535 |
| Chenghou Project | 982 | 960 | 755 | 71 | 0 | 14 | 20 | 976 | 696 |
| Blue Ridge | 970 | 949 | 830 | 67 | 0 | 3 | 25 | 964 | 690 |
| Sinucit | 609 | 590 | 499 | 46 | 0 | 4 | 8 | 603 | 0 |
| Sebenco Climb | 974 | 955 | 699 | 59 | 0 | 9 | 6 | 968 | 708 |
| Sol 2 | 803 | 782 | 584 | 125 | 0 | 6 | 95 | 797 | 529 |
| TEAM SELECTION | 67 | 40 | 0 | 0 | 0 | 0 | 0 | 67 | 0 |

(Fog is drawn by the port; it is in the table for scale. Every textured draw of these frames uses the modulate
texture function, so TEXENVCOLOR never matters there.)

What that means for the picture, from the most draws to the fewest:

- **Mipmaps.** 70 to 87% of a race frame's textured draws carry two to five mip levels (TEXADDR1 to 4, TEXSIZE1
  to 4, TEXLEVEL mode 2 "slope" with a per-draw LOD slope, TEXLODSLOPE), and the PSP picks a smaller level as a
  surface recedes. The port always samples level 0, so distant textures (grandstand crowds, the track's far surface,
  building windows) are sharper and shimmer in motion where the PSP's are smooth: the clearest single difference in
  the race shots (Blue Ridge's grandstand, "The differences"). The levels themselves are plain reductions: decoded
  from the Sebenco Climb dump, a wall texture's four levels have the same mean colour.
- **Environment and projection mapping** (TEXMAPMODE 2 and 1, TEXSHADELS): 7 to 16% of a race frame's draws take
  their texture coordinates from the normals (a reflection) or, on Vineta K, from the texture matrix. The port draws
  them with the vertices' own coordinates, so the ships' hulls and canopies, glass buildings and shiny roofs lose or
  misplace their reflections.
- **Dithering** (DITHERENABLE, DITH1 to 4): 6 to 95 draws a race frame. The PSP dithers when it writes 16-bit
  colour; most race targets are 32-bit, where it does nothing, and the 565 billboard target is the exception. Small.
- **The colour test** (COLORTESTENABLE, COLORTEST, COLORREF, COLORTESTMASK): 3 to 14 draws a race frame, always
  "not equal to black" with the full mask: the PSP drops the pixels that come out pure black. They draw into the
  565 billboard target (the screens beside the track) and a few small objects of the scene. The port keeps those
  black pixels; no difference was found in the shots, so this one is a check rather than a known defect.
- **Depth clamp** (CLIPENABLE): set for every 3D draw. The PSP clamps depth to the range instead of clipping
  against the far plane; the port clips. Shows only where geometry crosses the depth range's ends.
- **Regions, flat shading, logic ops, morph weights, patches, the GE init's undocumented F0 to F9**: written a few
  times at start-up or with their reset values (`first=0x0`, one write a run); no draw of the frames read used
  them.

### Imports with no implementation

26 of the 278 imports have no implementation (the start-up list in every log: `sceKernelLoadExec`, the alarm and
semaphore-status calls, ten `sceHttp*`, the adhoc matching and PDP stat calls, `sceParseHttpStatusLine`,
`sceUriParse`, `sceRtcGetTime_t`, `sceRtcSetTime_t` and the four `sceUtilityGameSharing*`). None was called in any
cell: a call would print `[hle-stub]`, and with `PURE_STRICT_HLE=1` stop the cell as HALT. They belong to the
multiplayer, the download menu's network side and game sharing, which no cell reaches.

## PPSSPP references beyond the five (item 3)

New routes in `tools/ppsspp/routes/` reach every scene of the brief in PPSSPP with frame-exact input; the captures
are listed in `ref/README.md` with their hashes and the commands that make them. A port capture of the same game
moment was made for each, headless on the Metal backend: by the suite's own routes where `config/pad_scripts/` has
one, by ad-hoc presses otherwise (the steps are in the table). Scenes with a port route are now rows of
`tools/frame_regress.sh` (thirteen; "Re-baselining" in docs/verification.md for their measured values); the others
need a route file in `config/pad_scripts/`, which this task could not add (Must not touch), so their fractions are
here only.

How the moments were matched: the frontend runs at two vblanks a frame on both, so a menu `k` frames after its
press is PPSSPP vblank `V + 2k` for port flip `F + k`; each menu pair was then confirmed by searching a burst of port
captures for the PPSSPP frame (every menu matched at a fraction of 0.0000 at tol 24, the Metal backend drawing the
2D screens exactly). Race and Zone scenes are the first frame with the HUD fully faded in, found on both sides from
the CURRENT and LAP labels' brightness (`tools/hud_check.py`'s regions) or, in Zone, the SCORE label's. The zone
change is the first frame with ZONE 2 on both: the score counts one a flip on both and jumps by 501 at the change (299
to 800), so the frame with SCORE 800 is the same game moment, port flip 5679 and PPSSPP vblank 7528. With Cross held
the ship has stopped at the first barrier by then, so the frame holds the 3D at rest and the HUD; what differs is the
3D (the ship's environment map, the mip levels).

A PPSSPP capture made while the CPU is held at a breakpoint lets PPSSPP's file reads run on in real time, so a
capture during a load makes the load end sooner in emulated time and moves everything after it (two runs of
`zone_start.txt`, one with a capture every 10 vblanks and one with none during the load, put the race 100 vblanks
apart). Every race reference was therefore taken in a run with no capture between the route's last menu press and
the scene. A capture on a menu before the load does not move the race (a Time Trial run with a capture and GE dump
on TRACK SELECTION and one without captured the same race frame). A burst names its files after the frames it asked
for, and in a 30-fps scene a burst asking for every vblank falls behind (each capture holds the game over two flips):
the race references' vblanks below are the ones the runs logged, `ref/README.md` has the details.

Fractions are the share of pixels differing by more than the tolerance (`tools/imgdiff.py`), both at 480x272. Port
flips are of the headless Metal run; "+ steps" are presses added to the named `config/pad_scripts/` routes.

| Scene | PPSSPP (route after frontend.txt, vblank) | Port (route, flip) | Tol | Fraction | In the suite |
|---|---|---|---|---|---|
| SINGLE PLAYER | vineta_k_start.txt, 5850 | main_menu.txt + single_race.txt, 4765 | 24 | 0.0000 | `single_player` |
| CLASS SELECTION | vineta_k_start.txt, 6050 | the same, 4990 | 24 | 0.0000 | `class_select` |
| LEAGUE SELECTION | vineta_k_start.txt, 6250 | the same, 5185 | 24 | 0.0000 | `league_select` |
| TRACK SELECTION | vineta_k_start.txt, 6450 | the same, 5390 | 24 | 0.0000 | `track_select` |
| TEAM SELECTION | vineta_k_start.txt, 6690 | the same, 5600 | 24 | 0.0000 | `team_select` |
| Time Trial TRACK SELECTION | time_trial_start.txt, 6650 | main_menu.txt + time_trial.txt, 5375 | 24 | 0.0000 | `tt_track_select` |
| Time Trial, first full HUD, Vineta K | time_trial_start.txt, 7340 | the same, 5890 | 32 | 0.0617 | `tt_hud` |
| Free Play TRACK SELECTION | free_play_start.txt, 6650 | main_menu.txt + free_play.txt, 5375 | 24 | 0.0000 | `fp_track_select` |
| Free Play, first full HUD, Vineta K | free_play_start.txt, 7340 | the same, 5890 | 32 | 0.0620 | `fp_hud` |
| TOURNAMENT SELECTION | tournament_start.txt, 6450 | main_menu.txt + tournament.txt, 5185 | 24 | 0.0000 | `tournament_select` |
| Zone TRACK SELECTION | zone_start.txt, 6250 | main_menu.txt + zone.txt, 4975 | 24 | 0.0000 | `zone_track_select` |
| Zone 1, first frame with the HUD | zone_start.txt, 6694 | the same, 5260 | 32 | 0.0348 | `zone_hud` |
| Zone 1's first zone change (ZONE 2, SCORE 800; the ship stopped at the first barrier) | zone_start.txt, 7528 | the same, 5679 | 32 | 0.0649 | `zone_change` |
| Zone 1's end panel (TOTAL ZONES CLEAR 6, TOP SPEED 405.07 / 404.68, SCORE 4292 / 4291) | zone_start.txt, 11000 | the matrix's `zone-zone_1` end shot | 32 | 0.0181 | no (the sweep's shot) |
| OPTIONS | options_controls.txt, 6550 | main_menu.txt + 4700, 4740 DOWN, 4800 Cross, 4950 to 5040 four DOWN, 5100 Cross; 5155 | 24 | 0.0000 | no route |
| CONTROLS | options_controls.txt, 6900 | the same + 5300 Cross; 5375 | 24 | 0.0000 | no route |
| Modesto Heights, first full HUD | vineta_k_start.txt + track_down1.txt, 7158 | main_menu.txt + single_race.txt + 5380 DOWN; 6016 | 32 | 0.0388 | no route |
| Chenghou Project, first full HUD | + track_down2.txt, 7158 | + 5380, 5410 DOWN; 6016 | 32 | 0.0326 | no route |
| Blue Ridge, first full HUD | + track_down3.txt, 7158 | + 5380, 5410, 5440 DOWN; 6016 | 32 | 0.0534 | no route |
| Sinucit, first full HUD | unlock_all + unlock_race_beta, 7662 | the sweep's picks with `PURE_TEST_UNLOCK_ALL=1`; 6016 | 32 | 0.1163 | no route |
| Citta Nuova | + unlock_track_down1, 7664 | 6018 | 32 | 0.0374 | no route |
| Sebenco Climb | + unlock_track_down2, 7670 | 6018 | 32 | 0.3207 | no route |
| Sol 2 | + unlock_track_down3, 7652 | 6018 | 32 | 0.1188 | no route |
| Karbonis | unlock_all + unlock_race_classic, 7636 | 6016 | 32 | 0.0312 | no route |
| Sagarmatha | + unlock_track_down1, 7638 | 6016 | 32 | 0.0338 | no route |
| Manor Top | + unlock_track_down2, 7640 | 6016 | 32 | 0.0645 | no route |
| Mandrashee | + unlock_track_down3, 7640 | 6016 | 32 | 0.0622 | no route |
| The pause menu, Vineta K | vineta_k_start + vineta_k_hold_cross + pause.txt, 7880 | main_menu.txt + single_race.txt + 6700 `pad start`; 6720 | 32 | 0.1185 (the menu itself identical; the race behind it 0.2 s apart: 0:07.4 against 0:07.6) | no route |
| The results panel after Vineta K | `--ppsspp-race vineta_k`, finish + 240 | the matrix's `single_race-vineta_k` results shot | 32 | 0.74 (two different races: the panel's layout, fonts, LR/RR marks and yellow best lap the same, the times and the replay behind differ) | no |
| The system save dialog | save_yes.txt, 5200 and 5400 | none: the port draws no dialog | | | no |

The race-start scenes of the other tracks differ from PPSSPP by the 3D only (the HUD, its labels and digits, match):
see "The differences" for what. Sebenco Climb, Sol 2 and Sinucit stand out (0.32, 0.12, 0.12).

### The Beta and Classic circuits in PPSSPP: the game's own unlock code

PPSSPP's CWCheat engine has pointer writes (code type 6: a pointer at an address, a value, an offset), which should
reach the profile's unlock byte at `[0x08B17794] + 0x381` (not tried); GPI cannot be cheated, being no memory.
Neither is needed: the game has the unlock as a button sequence on MAIN MENU. FUN_0894d4c8, the MAIN MENU
page's update, compares each newly pressed button with the table at 0x08AB480C (codes 2, 3, 2, 8, 9, 8, 3, 2, 3, 9,
8, 9, -1); FUN_08898870 numbers the PSP's buttons 0 UP, 1 DOWN, 2 LEFT, 3 RIGHT, 4 CIRCLE, 5 CROSS, 6 TRIANGLE, 7
SQUARE, 8 L, 9 R. So **LEFT, RIGHT, LEFT, L, R, L, RIGHT, LEFT, RIGHT, R, L, R** on MAIN MENU sets the profile's
`+0x381` and shows "CONGRATULATIONS! YOU HAVE UNLOCKED: EVERYTHING"; any other button starts the sequence again.
`tools/ppsspp/routes/unlock_all.txt` enters it in PPSSPP and the port took it the same way (headless, the presses
from flip 4480, 30 apart: the same panel, then five classes on CLASS SELECTION, without `PURE_TEST_UNLOCK_ALL`).
`unlock_race_beta.txt`, `unlock_race_classic.txt` and `unlock_track_downN.txt` then reach every Beta and Classic
circuit, and their first full-HUD frames are in `ref/` (PNG only) and in the table above. The port's side of those
eight used the sweep's picks with the test switch; the profile byte set by the code would be the more faithful
switch for the sweep (it is saved with the profile, as a player's would be).

## Audio (item 4)

Every cell ran with `PURE_AUDIO_WAV` (docs/verification.md, "Audio": the mix and one file per channel, on the
kernel's virtual clock, so a headless run records what the game hands sceAudio with no device open), and the tool ran
`tools/wavstats.py` over the mix, the sceSas channel (1) and the music channel (2) from the race start (the first
ship line with a running clock) to the cell's end, then removed the WAVs. `out/fidelity/audio.md`:

| cell | window s | mix active | mix clip | music (ch 2) active | music zero runs | sceSas (ch 1) active | sceSas clip | underruns |
|---|---|---|---|---|---|---|---|---|
| single_race-vineta_k | 196 | 1.00 | 0.000029 | 1.00 | 0 | 1.00 | 0.000036 | ch 3: 2 |
| single_race-modesto_heights | 286 | 1.00 | 0.000021 | 1.00 | 0 | 1.00 | 0.000033 | ch 3: 2 |
| single_race-chenghou_project | 160 | 1.00 | 0.000046 | 1.00 | 0 | 1.00 | 0.000071 | ch 3: 2 |
| single_race-blue_ridge | 268 | 1.00 | 0.000054 | 1.00 | 1 | 1.00 | 0.000072 | ch 1: 1, ch 2: 1, ch 3: 2 |
| single_race-sinucit | 169 | 1.00 | 0.000018 | 1.00 | 0 | 1.00 | 0.000020 | ch 3: 2 |
| single_race-citta_nuova | 330 | 1.00 | 0.000105 | 0.98 | 2 | 1.00 | 0.000141 | ch 2: 1, ch 3: 2 |
| single_race-sebenco_climb | 337 | 1.00 | 0.000034 | 0.98 | 2 | 1.00 | 0.000042 | ch 2: 1, ch 3: 2 |
| single_race-sol_2 | 251 | 1.00 | 0.000025 | 1.00 | 0 | 1.00 | 0.000032 | ch 3: 2 |
| single_race-karbonis | 246 | 1.00 | 0.000007 | 1.00 | 0 | 1.00 | 0.000011 | ch 3: 2 |
| single_race-sagarmatha | 221 | 1.00 | 0.000000 | 1.00 | 0 | 1.00 | 0.000000 | ch 1: 2, ch 2: 2, ch 3: 2 |
| single_race-manor_top | 90 | 1.00 | 0.000001 | 1.00 | 0 | 1.00 | 0.000000 | ch 3: 2 |
| single_race-mandrashee | 253 | 1.00 | 0.000001 | 1.00 | 1 | 1.00 | 0.000001 | ch 1: 2, ch 2: 1, ch 3: 2 |
| single_race-vineta_k-phantom | 339 | 1.00 | 0.000017 | 0.98 | 2 | 1.00 | 0.000015 | ch 2: 1, ch 3: 2 |
| single_race-modesto_heights-phantom | 471 | 1.00 | 0.000026 | 0.99 | 2 | 1.00 | 0.000028 | ch 2: 1, ch 3: 2 |
| single_race-chenghou_project-phantom | 461 | 1.00 | 0.000008 | 0.98 | 2 | 1.00 | 0.000014 | ch 2: 1, ch 3: 2 |
| single_race-blue_ridge-phantom | 445 | 1.00 | 0.000040 | 0.98 | 2 | 1.00 | 0.000056 | ch 2: 1, ch 3: 2 |
| single_race-sinucit-phantom | 53 | 1.00 | 0.000000 | 1.00 | 0 | 1.00 | 0.000000 | ch 3: 2 |
| single_race-citta_nuova-phantom | 596 | 1.00 | 0.000055 | 0.98 | 3 | 1.00 | 0.000061 | ch 1: 1, ch 2: 3, ch 3: 2 |
| single_race-sebenco_climb-phantom | 463 | 1.00 | 0.000012 | 0.98 | 2 | 1.00 | 0.000013 | ch 1: 1, ch 2: 2, ch 3: 2 |
| single_race-sol_2-phantom | 408 | 1.00 | 0.000049 | 0.98 | 2 | 1.00 | 0.000052 | ch 1: 1, ch 2: 2, ch 3: 2 |
| single_race-karbonis-phantom | 133 | 1.00 | 0.000000 | 1.00 | 0 | 1.00 | 0.000000 | ch 3: 2 |
| single_race-sagarmatha-phantom | 349 | 1.00 | 0.000002 | 0.98 | 2 | 1.00 | 0.000004 | ch 2: 1, ch 3: 2 |
| single_race-manor_top-phantom | 197 | 1.00 | 0.000025 | 1.00 | 0 | 1.00 | 0.000026 | ch 3: 2 |
| single_race-mandrashee-phantom | 311 | 1.00 | 0.000000 | 1.00 | 0 | 1.00 | 0.000000 | ch 3: 2 |
| time_trial-vineta_k | 212 | 1.00 | 0.000000 | 1.00 | 0 | 1.00 | 0.000000 | ch 3: 2 |
| time_trial-modesto_heights | 347 | 1.00 | 0.000000 | 0.98 | 3 | 1.00 | 0.000000 | ch 1: 2, ch 2: 3, ch 3: 2 |
| time_trial-chenghou_project | 305 | 1.00 | 0.000000 | 1.00 | 0 | 1.00 | 0.000000 | ch 1: 1, ch 2: 1, ch 3: 2 |
| time_trial-blue_ridge | 320 | 1.00 | 0.000000 | 1.00 | 0 | 1.00 | 0.000000 | ch 3: 2 |
| time_trial-sinucit | 42 | 1.00 | 0.000000 | 1.00 | 0 | 1.00 | 0.000000 | ch 3: 2 |
| time_trial-citta_nuova | 411 | 1.00 | 0.000000 | 0.98 | 2 | 1.00 | 0.000000 | ch 2: 1, ch 3: 2 |
| time_trial-sebenco_climb | 437 | 1.00 | 0.000000 | 0.98 | 2 | 1.00 | 0.000000 | ch 2: 1, ch 3: 2 |
| time_trial-sol_2 | 331 | 1.00 | 0.000000 | 0.98 | 2 | 1.00 | 0.000000 | ch 2: 1, ch 3: 2 |
| time_trial-karbonis | 239 | 1.00 | 0.000000 | 1.00 | 0 | 1.00 | 0.000000 | ch 3: 2 |
| time_trial-sagarmatha | 255 | 1.00 | 0.000000 | 1.00 | 0 | 1.00 | 0.000000 | ch 3: 2 |
| time_trial-manor_top | 96 | 1.00 | 0.000000 | 1.00 | 0 | 1.00 | 0.000000 | ch 3: 2 |
| time_trial-mandrashee | 286 | 1.00 | 0.000000 | 1.00 | 0 | 1.00 | 0.000000 | ch 3: 2 |
| free_play-vineta_k | 221 | 1.00 | 0.000000 | 0.99 | 1 | 1.00 | 0.000000 | ch 1: 2, ch 2: 2, ch 3: 2 |
| free_play-sol_2 | 321 | 1.00 | 0.000000 | 0.99 | 2 | 1.00 | 0.000000 | ch 1: 1, ch 2: 1, ch 3: 2 |
| free_play-karbonis | 270 | 1.00 | 0.000000 | 0.99 | 1 | 1.00 | 0.000000 | ch 3: 2 |
| tournament-alpha | 1091 | 1.00 | 0.000024 | 0.98 | 7 | 1.00 | 0.000032 | ch 2: 3, ch 3: 2 |
| tournament-beta | 40 | 1.00 | 0.000000 | 1.00 | 0 | 1.00 | 0.000000 | ch 3: 2 |
| tournament-classic | 543 | 1.00 | 0.000001 | 0.97 | 4 | 1.00 | 0.000001 | ch 1: 1, ch 2: 2, ch 3: 2 |
| zone-zone_1 | 67 | 1.00 | 0.000009 | 1.00 | 0 | 1.00 | 0.000006 | ch 3: 2 |
| zone-zone_2 | 67 | 1.00 | 0.000001 | 1.00 | 0 | 1.00 | 0.000000 | ch 3: 2 |
| zone-zone_3 | 70 | 1.00 | 0.000000 | 1.00 | 0 | 1.00 | 0.000000 | ch 3: 2 |
| zone-zone_4 | 69 | 1.00 | 0.000014 | 1.00 | 0 | 1.00 | 0.000003 | ch 1: 1, ch 2: 1, ch 3: 2 |

Over the 46 cells (3.6 h of audio from the race starts):

- **The mix is active in every second of every race** (1.00 in all 46), and so is the sceSas channel; no cell has a
  zero run in the mix.
- **Clipping is rare**: at most 0.000105 of the mix's samples (Citta Nuova at Vector) and 0.000141 of the sceSas
  channel's, in the races with AI ships and their weapons; none at all in the 12 Time Trial and the three Free Play
  cells, where the player is alone. In 41 cells the sceSas channel holds as many clipped samples as the mix or more,
  so the clipping is in what the SAS mixer hands the game, before sceAudio (in Zone and two races the mix clips a
  little more than its parts, the music adding to the effects); whether the PSP's own mixer clips at those moments
  too was not measured (the main menu's attract demo clips more: below).
- **The music channel is active in 97 to 100% of the seconds.** Its silences of 50 ms or more are of three kinds:
  - the change of music track: 177 ms, then 2.15 s of silence at 524.7 to 527.3 s of virtual time in all 14 cells
    besides the tournaments that run that long (within 0.1 s in each, about 5:24 into the race music, so the same
    tracks in the same order), then the channel 2 underrun of 10 to 60 ms as the next track starts; the later changes
    (the tournaments, whose music stops for each load, and Citta Nuova at Phantom) have shorter silences, 0.6 to 1.0 s
    at 636, 755, 932 and 1224 s. Difference 8: whether a PSP has the same gap needs PPSSPP's audio (`DumpAudio`),
    not measured here;
  - the loads between a tournament's races (5.95 to 6.02 s), where the game stops its music; and in Free Play 3.9 s
    from the moment the ship crosses the finish line (Vineta K: the laps add up to 212.8 s, the silence starts at
    213.1 s of race clock) until the results screen, which Time Trial and Single Race do not have (also difference
    8, to compare);
  - the hitches (81 to 239 ms; previous section, difference 7).
- Underruns, the capture's own count per channel over the whole run, are those of the previous section: two on the
  movie channel at boot in every cell, and the hitches and music changes.

### Five minutes idle on the main menu

`main_menu.txt` headless to flip 13500 with `PURE_AUDIO_WAV` (320.6 s of virtual time; the main menu from about
145 s). The frontend music starts at 145.5 s, as in task 013. Left alone for 30 s the main menu launches the attract
demo (FUN_0894d4c8: no new button for 30 s of its timer, "Demo Launch"): a race on Modesto Heights, and after it a
second on Citta Nuova (the TrackStartup.xml each opens). The music channel stops for the demo's load (175.5 s, 9 s of
silence on channel 2 while the sceSas channel carries the demo's sound) and again for the second demo (295.7 s, 9
s). Over 146 to 320.7 s the mix is active in every second (174 of 174), with no zero run of 50 ms or more; the music
channel is active 156 of 174 seconds, the two loads its only silences.

The mix clips in the demos' races: 2611 samples at full scale over the window (0.017%), in nine seconds between 202
and 276 s, up to 1000 samples in one second, and the sceSas channel itself holds 3474 clipped samples: the clipping is
in what the sceSas mixer hands the game, before sceAudio. The scripted races clip far less (the single-race cells'
mix 0.00003 or less). Whether the PSP's own SAS mixer clips there too was not measured (PPSSPP can dump its audio,
`DumpAudio` in its ini, not used here).

## Saves and records (item 5)

Every cell starts from an empty memory stick and makes a profile (`main_menu.txt`: NEW, NAME0000, AAA, SAVE PROFILE
YES), so every log has the first-boot AUTOSAVE of `PPCD00001DLS001` and the NEW profile's LISTSAVE of
`UCUS98612P0000`; the matrix's `saves` column lists anything beyond those two. The Single Race cells quit at their
results panel, before the game saves; so two runs went on past it:

- **After a Single Race**: a cell of the audit's `single_race_save` mode (Single Race's route with the Tournament's
  end rule: Cross every 120 flips after the results panel; `--cells` with `single_race_save vineta_k`). After the
  panel (BAD LUCK... 7TH, the laps 1:06.77, 0:59.66, 0:59.96, TOTAL 3:06.39, LR and RR marks, ENTER TAG AAA) the
  game shows PROFILE AUTOSAVED and saves: `[savedata] AUTOSAVE (1) game="UCUS98612" save="P0000"
  file="PROFILE.BIN"`, 41570 bytes, the same size as at NEW. Then RETURN TO MAIN MENU / RACE AGAIN / NEXT RACE. Its
  TRACK SELECTION, back in the menus, shows RACE RECORD 3:08.59 and LAP RECORD 0:58.69 for Vineta K.
- **After the Alpha tournament** (the matrix's `tournament-alpha` cell): PROFILE AUTOSAVED and an AUTOSAVE of
  `P0000/PROFILE.BIN` after races 1, 2 and 3; the cell ends on the final TOURNAMENT STANDING, before the fourth.

Then a reboot that LOADs the saved profile (headless: `profile_load.txt`'s first steps, the title and LOAD, on a copy
of the cell's memory stick, then MAIN MENU > PROFILE > PROGRESS, RECORDS > RACE (paged with RIGHT), STATS, and
SINGLE PLAYER > TIME TRIAL > TRACK SELECTION):

| Screen | New profile | After the Single Race, LOADed | After the tournament, LOADed |
|---|---|---|---|
| RACE RECORDS, Vineta K, Vector | 1ST, 2ND, 3RD and BEST LAP 0:00.00 | 1ST AAA 3:08.59 FEISAR, BEST LAP AAA 0:58.69 FEISAR | 1ST AAA 3:03.60 FEISAR, BEST LAP AAA 0:59.12 FEISAR |
| RACE RECORDS, Modesto Heights / Chenghou Project / Blue Ridge | 0:00.00 | 0:00.00 | 4:40.40 and 1:29.06 / 4:19.22 and 1:19.00 / 0:00.00 (race 4 not autosaved) |
| PROGRESS (the medal grid per track and class) | ROOKIE (0), no medal | ROOKIE (0), no medal (7th) | ROOKIE (0), no medal (8th overall) |
| STATS | every time 00:00:00, medals 0 | TOTAL and SINGLE RACE PLAY TIME 00:03:08 | TOTAL and TOURNAMENT PLAY TIME 00:12:04 |
| Time Trial's TRACK SELECTION | RACE and LAP RECORD 0:00.00 | the same (no Time Trial run) | |

The records the reboot shows are the ones the race set (the tournament's Vineta K: 64.6 + 59.1 + 59.9 s = 3:03.6),
so the autosave, the files under `ms0/PSP/SAVEDATA/UCUS98612P0000/` and LOAD round-trip the progress. No medal was
won by any cell (the follower finishes 7th or 8th, and Time Trial's bronze at Vineta K is 2:10.00 against its
3:23 to 3:33), so medal counting is untested.

### Two profiles in a row, and the PSP's save list

`main_menu.txt` then MAIN MENU > PROFILE > NEW > YES on the same stick (SET NAME comes pre-filled with the current
name, and the same presses made it NAME1111), SAVE PROFILE YES, then PROFILE > LOAD, with `PURE_TRACE_SAVEDATA=1`:

- the second LISTSAVE asks for the list `P0000` to `P0004` with `overwrite=0` and the framework answers it by writing
  `P0000` again: the first profile (NAME0000) is gone, and the stick holds one profile, NAME1111;
- LISTLOAD then loads `P0000`, the only save, without a list on screen.

What a PSP shows instead, from PPSSPP (`frontend.txt` + `save_yes.txt`, which answers YES on SAVE PROFILE; shots
every 10 vblanks from 5100, `ref/save_dialog.png` and `ref/save_completed.png`): the system's save dialog takes the
screen, titled Save, with the game's list as a column of entries, here five NEW DATA slots with the game's empty
profile icon, and "× Enter ○ Back"; the player picks a slot (the route's next Cross took the first), and the dialog
says "Save completed." beside the profile's icon, "Profile data", the date and 366 KB, until ○ Back closes it. With a
profile on the stick its entry would sit in that list with its icon and the "User name: ..." detail, and LOAD's
dialog lists the saves to pick from. The port shows none of this: the game's PROFILE page stays up while the
framework answers in a few polls, picks the first slot to write and the first existing save to load, and never
asks before writing over one.

PPSSPP's save also differs in its bytes: its `PROFILE.BIN` is 41586 bytes of ciphertext and its `PARAM.SFO` lists
the file in `SAVEDATA_FILE_LIST` (the list a PSP keeps of its encrypted files), while the port writes the 41570 plain bytes with an empty
list (task 014 took the game's 0x5DC-byte parameter block, which has no key field, to mean the PSP leaves the file
plain; PPSSPP encrypts it with the PSP's no-key savedata encryption). The other five files are byte-for-byte the
same size. So a save made on a PSP (or in PPSSPP) will not load in the port, which would read the ciphertext as a
profile, and a port save copied to a PSP would not load there. The PPSSPP save was moved out of its memory stick
afterwards, as the routes expect none.

## The two-vblank stretches (item 6): the game's own rule, and PPSSPP has them too

Task 033 found that every race runs 0.4 to 1.3 s at a time at two vblanks a frame, the end-of-frame routine's locked
path (docs/timing.md, step 5: FUN_0886511c waits two vblanks when the frame object's byte `+0x116c` is 0 or its
countdown at `+0x117c` is not 0, and decrements the countdown). This audit found what sets the lock in a race, and
measured PPSSPP at the same game moments. **Finding: the stretches are the game's own; nothing in the HLE's timing
starts them; PPSSPP shows the same stretches, the same length, for the same reason.**

### What writes the two fields

The frame object is the one `DAT_08a8e960` points to. Every store to its `+0x116c` and `+0x117c` in the corpus
(found in `generated/` by the stores at offsets 4460 and 4476, then decompiled in Ghidra from a copy of the main
checkout's project, `analyzeHeadless ... -process BOOT.BIN -noanalysis -readOnly -postScript Decompile.java OUT
ADDR...`, since Ghidra refuses a path with `.claude` in it):

| Writer | Field | Value | When |
|---|---|---|---|
| BackendRoot_cpp__0880c068 (the race backend's constructor) | `+0x116c` | 1 | a race starts: free-running frames from here (the 60-fps modes) |
| BackendRoot_cpp__0880c328 (its destructor) | `+0x116c` | 0 | the race is torn down: back to the frontend's 30 fps |
| LinkObj_etc__08818d80 (SPFreePlay_RaceManager.cpp's constructor), LinkObj_etc__08819a0c, LinkObj_etc__0881bc8c (two more race managers of the same shape) | `+0x116c` | 0 | Free Play and the other 30-fps modes lock again after the backend set 1 |
| RenderManager_cpp__088666c4 | both | 0, 0 | render manager set-up |
| FUN_08897f20, FUN_08896d7c, FUN_08896e30 (MemStickUtil.cpp's dialog driver) | `+0x116c` | `DAT_08b17c14` (the mode saved before a save dialog) | a save or load dialog ends |
| **FUN_0882da04 (FxScreen.cpp's update, after its constructor FxScreen_cpp__0882d8fc)** | `+0x117c` | **2, every frame its effect runs** | a full-screen flash is on screen |
| FUN_0886511c (the end-of-frame routine) | `+0x117c` | the countdown less 1 | each locked frame |

FxScreen (`c:/Work/Wipeout/Code/System/Particles/FxScreen.cpp`) is a full-screen colour flash with keyframed colour
and a duration. While its time runs from 0 to 1 it queues itself for drawing (FUN_08865358, sort key 0x4e000000) and
sets the countdown to 2, so every frame of the flash and the one after it wait two vblanks. Its strength falls off
with the camera's distance from the flash's position (FUN_0882e58c: `1 - (|camera - position| - near) / (far -
near)`, clamped), and a new flash replaces the running one only if it is stronger. The one FxScreen object is made in
the race set-up (Fog_etc__0880c748, pointer at `DAT_08a8ce44`); the code that reads that pointer, so the code that
starts flashes, is in MineManager.cpp, MissileManager.cpp, RocketManager.cpp, Bomb.cpp, DisruptorFx.cpp,
Quake_Importer.cpp (the weapons' explosions), FUN_08928824 (the ship destroyed), the ship's own code (LinkObj_h__08923db4,
LinkObj_h__089258b8), RaceManager (FUN_088125a4) and BackendRoot. So a stretch is a weapon going off near the camera,
the player's ship falling off the track and being put back, or the race-start fade.

### In the port's races

The matrix collects every stretch (`out/fidelity/stretches.md`; the table below). Two lengths recur:

- **31 or 32 flips (1.03 s)**, the same length each time: the ship leaving the track and the game putting it back
  (Sinucit, race 1 of the Beta tournament: five at 897 to 969 m, each one of the put-backs the sweep counted), and at
  Phantom on Vineta K ten at 108 to 167 m in laps 1, 3, 4 and 5, where the follower at Phantom speed loses the track.
- **13 to 25 flips (0.4 to 0.8 s)** at places that change from run to run: weapons going off near the player (the AI
  ships fire at it, and the follower fires whatever it picks up: its steering tables' `absorb=2` presses Square every
  two seconds, which the game's controls screen names Use pickup).

Over the 27 cells of the 60-fps modes (Single Race and Tournament; Time Trial, Free Play and Zone run at two vblanks
a flip throughout, so they cannot show one): 290 stretches, 273 s in all. `out/fidelity/stretches.md` lists each one
with its race, lap, track distance and speed; per cell, by length:

| Cell | Stretches | Seconds in all | 10 to 28 flips | 31 or 32 | 35 to 40 | over 40 | Longest (flips, s) |
|---|---|---|---|---|---|---|---|
| single_race-vineta_k | 3 | 2.1 | 3 | 0 | 0 | 0 | 23, 0.77 |
| single_race-modesto_heights | 5 | 3.5 | 4 | 0 | 1 | 0 | 38, 1.27 |
| single_race-chenghou_project | 6 | 5.0 | 4 | 2 | 0 | 0 | 31, 1.03 |
| single_race-blue_ridge | 8 | 7.3 | 6 | 0 | 0 | 2 | 48, 1.60 |
| single_race-sinucit | 11 | 11.2 | 1 | 9 | 1 | 0 | 39, 1.30 |
| single_race-citta_nuova | 6 | 4.4 | 5 | 1 | 0 | 0 | 31, 1.03 |
| single_race-sebenco_climb | 2 | 1.0 | 2 | 0 | 0 | 0 | 16, 0.53 |
| single_race-sol_2 | 1 | 0.5 | 1 | 0 | 0 | 0 | 16, 0.53 |
| single_race-karbonis | 10 | 8.9 | 3 | 7 | 0 | 0 | 32, 1.07 |
| single_race-sagarmatha | 3 | 3.1 | 1 | 1 | 0 | 1 | 44, 1.47 |
| single_race-manor_top | 10 | 10.7 | 0 | 9 | 1 | 0 | 40, 1.33 |
| single_race-mandrashee | 2 | 2.2 | 0 | 1 | 1 | 0 | 35, 1.17 |
| single_race-vineta_k-phantom | 14 | 12.6 | 4 | 10 | 0 | 0 | 32, 1.07 |
| single_race-modesto_heights-phantom | 22 | 19.8 | 15 | 4 | 0 | 3 | 63, 2.10 |
| single_race-chenghou_project-phantom | 40 | 41.7 | 7 | 28 | 2 | 3 | 93, 3.10 |
| single_race-blue_ridge-phantom | 6 | 3.8 | 6 | 0 | 0 | 0 | 24, 0.80 |
| single_race-sinucit-phantom | 13 | 13.4 | 0 | 13 | 0 | 0 | 31, 1.03 |
| single_race-citta_nuova-phantom | 17 | 12.0 | 15 | 1 | 1 | 0 | 38, 1.27 |
| single_race-sebenco_climb-phantom | 6 | 6.5 | 3 | 0 | 2 | 1 | 57, 1.90 |
| single_race-sol_2-phantom | 19 | 19.7 | 2 | 15 | 1 | 1 | 44, 1.47 |
| single_race-karbonis-phantom | 16 | 16.7 | 7 | 7 | 1 | 1 | 118, 3.94 |
| single_race-sagarmatha-phantom | 4 | 4.6 | 3 | 0 | 0 | 1 | 81, 2.70 |
| single_race-manor_top-phantom | 23 | 23.2 | 4 | 17 | 2 | 0 | 39, 1.30 |
| single_race-mandrashee-phantom | 9 | 9.6 | 4 | 1 | 3 | 1 | 82, 2.74 |
| tournament-alpha | 17 | 15.2 | 10 | 2 | 5 | 0 | 39, 1.30 |
| tournament-beta | 6 | 5.7 | 1 | 5 | 0 | 0 | 31, 1.03 |
| tournament-classic | 11 | 9.0 | 4 | 7 | 0 | 0 | 31, 1.03 |
| all | 290 | 273.4 | 115 | 140 | 21 | 14 | |

Besides the two lengths above there is a third that recurs on ten of the twelve circuits, **38 or 39 flips (1.27 to
1.30 s)**, 17 of the 21 stretches of 35 to 40 flips; and **14 longer ones of 43 to 118 flips (up to 3.9 s)**, eleven
of them at Phantom (Karbonis 118, Chenghou Project 93, Mandrashee 82, Sagarmatha 81), where the follower leaves the
track more often. A stretch lasts while one flash follows another (FxScreen sets the countdown again on every frame its
effect runs, and a stronger flash replaces a running one), so the long ones are flashes back to back; which event makes
the 38-to-39-flip flash was not looked into. Phantom doubles the share: in Single Race the stretches take 4.3% of the
race clock at Phantom (184 s of 4230 s) against 2.1% at Vector (60 s of 2811 s).

A race with Cross held and no steering, where the player stops at the first barrier and no weapon comes near, has
none: `main_menu.txt` + `single_race.txt` headless to flip 9300 (51 s of race), and PPSSPP's `vineta_k_hold_cross.txt`
(50 s), both zero.

### In PPSSPP

`tools/fidelity_audit.py --ppsspp-race vineta_k` drives PPSSPP through the frame-exact routes to the Vineta K grid and
then steers the race with the sweep's own follower (the same steering table, the race record read from PPSSPP's memory
about 30 times a second, the stick and Square sent live), while log-only breakpoints log every flip with its emulated
time, every pass through the locked path (0x08865254) and every store of FxScreen's countdown (0x0882E198):

| Run | Laps (s) | Contacts | Two-vblank stretches (flips, s) | FxScreen stores in them | Locked passes in them |
|---|---|---|---|---|---|
| PPSSPP, `--ppsspp-race vineta_k` | 65.2, 59.3, 61.6 | 45 | 22 (0.73), 25 (0.83), 25 (0.83) | 21, 24, 24 (every flip but the first) | 22, 25, 25 |
| port, `single_race-vineta_k` of the matrix | 66.7, 59.6, 59.9 | 45 | 16 (0.53), 23 (0.77), 23 (0.77) | (no probe) | |

The follower drove both the same way (laps within 1.5 s and the same contact count), and both races had three
flashes of the same length. Where they fall differs because the weapons do (the AI ships' choices differ run to run
on both). The race start matches flip for flip: after the load both run 57 flips at two vblanks while the
race-start fade plays (PPSSPP logged 57 FxScreen stores there; the port's `PURE_TRACE_CALLS` trace of
`sceDisplaySetFrameBuf` shows 57 flips 33.4 ms apart, flips 5708 to 5764), then one vblank a flip.

What starts a stretch is a game event (an explosion, a put-back, the race start), not a time the game measures from
the system clock, and the lock lasts as long as the flash: the HLE's answers play no part, and PPSSPP shows the same
lengths. So this is faithful, and the list below has no row for it. A smoother race than the PSP's would be an
enhancement (the countdown store could be skipped, as the 60-fps cheat skips the second vblank wait), not a fix.
Open: the 31-flip put-back flash was measured only in the port (PPSSPP's race never left the track), and why the
follower at Phantom triggers one at about 150 m of Vineta K each lap was not looked into.

## The differences

Ordered by what a player would notice first. Each row is a candidate task; "size" is a guess (small: a day or less
in one file; medium: a feature across the backend or the framework's state; large: a subsystem). Eleven
differences: three in the race picture, two in the saves, one in loading, one in pacing and two in the audio (those
three still to confirm), two small GE states.

| # | What a player sees | Where | Evidence | Suspected cause | Size |
|---|---|---|---|---|---|
| 1 | Reflective surfaces look wrong: the ship's hull and canopy (always on screen), glass buildings, shiny roofs show the reflection texture stretched over the model instead of a reflection | every race and Zone, all the time; Sol 2's glass buildings and Sinucit's overhang most (0.12 of those frames) | the ship in the port's shots against PPSSPP's (Modesto Heights, Zone 1); 46 to 125 draws a race frame with TEXMAPMODE 2 in PPSSPP's dumps; TEXMAPMODE and TEXSHADELS in the framework's ignored list in every cell, 0.55 million writes a cell | backend feature: environment mapping (texture coordinates from the normals and the TEXSHADELS lights) and projection mapping (TEXMAPMODE 1, 40 draws on Vineta K) not carried by the framework's GE state (`ge_state.cpp`), not drawn by the Metal backend | medium |
| 2 | Distant textures are sharp and shimmer while moving (crowds, track surface, windows), where the PSP's are smooth | every race, worst on wide open tracks (Blue Ridge's grandstands) | Blue Ridge's first race frame against PPSSPP's (0.053 at tol 32 with the HUD equal); 70 to 87% of textured race draws carry mip levels in PPSSPP's dumps; TEXADDR1 to 7, TEXSIZE1 to 7, TEXLEVEL, TEXLODSLOPE ignored in every cell, 22.7 million writes a cell | backend feature: mipmaps (upload the levels the GE names, pick the level by the GE's LOD rule: TEXLEVEL mode 2 with the per-draw slope) | medium |
| 3 | Some surfaces are about 1.5 times brighter than on the PSP: Sebenco Climb's long concrete wall, Sinucit's overhang | Sebenco Climb (0.32 of the first race frame differs), Sinucit (0.12) | wall pixels (113, 125, 126) in the port against (70, 81, 83) in PPSSPP; the draws are unlit, fogged, vertex-coloured CLUT4 textures; the Vulkan backend draws the same pixels as the Metal one (a windowed run of the same frame), turning the port's fog or lighting off does not change them, and the mip levels have the same mean colour | unknown, upstream of both backends: the framework's GE state or vertex decode, or a GE rule neither backend applies; bisect from a PPSSPP GE dump of the frame (burst K's command of `ref/README.md` with `--gedump` at the Sebenco Climb frame; in this task's dump the wall was draws 197, 198 and 201) | small to medium (finding it) |
| 4 | Creating a second profile silently overwrites the first; LOAD offers no choice; no save dialog ever appears | the PROFILE menu, any player with more than one profile | `PURE_TRACE_SAVEDATA`: the second LISTSAVE (`overwrite=0`) writes P0000 again; PPSSPP shows the system save list (`ref/save_dialog.png`) and "Save completed." (`ref/save_completed.png`) | framework: `hle_savedata.cpp` answers LISTSAVE with the first listed name and LISTLOAD with the first save, with no dialog | medium (a list dialog in the framework's UI), small for the data loss alone (LISTSAVE with `overwrite=0` to the first free name) |
| 5 | A save from a PSP (or PPSSPP) does not load, and a port save would not load on a PSP | the memory stick | PPSSPP's `PROFILE.BIN` is 41586 bytes of ciphertext with the file in `SAVEDATA_FILE_LIST`; the port's 41570 bytes plain | framework: the PSP's savedata encryption (no-key mode) is not done | medium |
| 6 | Loading screens before a race are shorter than on the PSP (about 0.3 s of game time against 1.5 s in PPSSPP) | every race load | `PURE_TRACE_CALLS` on `sceDisplaySetFrameBuf` against PPSSPP's flip log | framework: file reads complete at once in emulated time, where PPSSPP (like the UMD) takes time over them; arguably welcome, but not 1:1 | small |
| 7 | The game freezes for 0.1 to 0.3 s now and then, with a gap in the sound | 12 of the 46 cells, one or two times each, at no fixed place (Zone 4 and Free Play Vineta K run again had them elsewhere) | race flips 102 to 295 ms after the one before, with sceSas and music underruns at the same moment and nothing else in the log (the matrix's hitches column, `out/fidelity-hitch/`) | unknown: the host holding the process (the machine was never idle), the sweep's pty reader holding the game's per-frame probe lines, or something of the port's own (the WAV capture, the backend's GPU waits); check on an idle machine in a run like a player's (a window, no probe lines, no WAV) with `PURE_METAL_TRACE` to see where the time goes | small (to check) |
| 8 | The race music stops for about 2 s when it changes tracks, with a 10 to 60 ms underrun as the next starts; in Free Play it stops for 3.9 s at the finish line | all long races at 524.7 to 527.3 s of game time (5:24 into the race music; shorter gaps at the later changes); every Free Play finish | music channel zero runs of 177 ms and 2.15 s at 524.7 and 525.1 s and an underrun at 527.3 s, the same in all 14 cells that get there; Free Play's silence from 213.1 s of race clock on Vineta K (the laps end at 212.8 s) | unknown: the game's own track change and finish, or the framework's sceAtrac feeding the new track late; compare with PPSSPP's audio dump (`DumpAudio`) | small (to check) |
| 9 | The attract demo's sound clips | the main menu left for 30 s | 3474 clipped samples in the sceSas channel over two demos; the scripted races at most 0.014% | unknown: the framework's SAS mix level, or the PSP clips too | small (to check) |
| 10 | Pure black pixels of a few draws (the billboard screens' content, a few small objects) are drawn where the PSP drops them | every race, 3 to 14 draws a frame | COLORTEST NOT EQUAL black in PPSSPP's dumps; ignored by the framework (7.7 million writes a cell) | framework GE state: the colour test | small |
| 11 | Dithering on 16-bit targets, depth clamping at the depth range's ends | every race | DITHERENABLE (6 to 95 draws a frame), CLIPENABLE (every 3D draw) in the dumps; ignored | framework GE state | small each |

Not differences, though they looked like ones:

- The two-vblank stretches (task 033): the game's own, and PPSSPP's (above).
- Zone's pace: a PPSSPP run with a capture every vblank seemed to count zones three times as fast, but a run with no
  capture during the race ends exactly as the port does (TOTAL ZONES CLEAR 6, SCORE 4292 against 4291): PPSSPP's
  captures moved its timing, not the port's.
- The movie channel's two 1.9 s underruns at boot in every cell: a reserved channel the game sends nothing for a
  while, silent on a PSP too.
- The follower's stalls (Sinucit's fork, Manor Top, Karbonis at Phantom, a wedge against a wall on Chenghou Project at
  4149 m): the game puts the ship back or holds it as it should; the test driver cannot get past.

Follow-ups that are not differences:

- Three render pipelines of the 30-fps modes' result and standings screens are missing from
  `config/metal_pipelines.txt` (made by a draw in every Time Trial, Free Play and Tournament cell that got that far):
  a pre-warm entry for each would rule out a first-use stall.
- The scenes with no route in `config/pad_scripts/` (OPTIONS, CONTROLS, the other Alpha circuits' and the Beta and
  Classic circuits' first race frames, the pause menu) could join the suite once a task may add the routes; their
  fractions are in the reference table above.
- The game's own unlock code (LEFT, RIGHT, LEFT, L, R, L, RIGHT, LEFT, RIGHT, R, L, R on MAIN MENU) sets the same
  profile byte as `PURE_TEST_UNLOCK_ALL`, and saves it with the profile, as a player's would be: the more faithful
  switch for the sweep.
- Medal counting is untested: no cell won a medal (the follower finishes 7th or 8th, and is far off Time Trial's
  bronze times).
- The 38-to-39-flip and the 31-flip (put-back) flashes were measured in the port only; PPSSPP's race had three
  flashes of 22 to 25 flips.
