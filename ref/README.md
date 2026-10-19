# Reference captures

PPSSPP reference material for frame comparison. Everything here except this file is git-ignored.

Made 2026-10-05 (task 006) with `tools/ppsspp/ppsspp_ctl.py` (docs/ppsspp.md): PPSSPP SDL 1.20.4 (brew cask
`ppsspp-emulator`), software renderer, rendering resolution 1x (480x272), frameskip off, game language English,
CROSS confirms, RTC base 2026-01-01 00:00 UTC, default compatibility settings. Memstick: `PSP/SAVEDATA/PPCD00001DLS001`
present, no profile save. The PNG is the displayed framebuffer read from VRAM (480x272 RGB); the `.ppdmp` is the GE
recording of the same frame (PPSSPP GE dump format, replayable in PPSSPP's GE debugger).

## Files and frames

Frames are vblank counts since boot. "Requested" is the `--shot`/`--gedump` frame; "captured" is the vblank position
of the flip that handed over the captured frame (`frame` in `ppsspp_run.json`). Three runs (two plain, one with HLE
logging) gave byte-identical PNGs, and the two plain runs byte-identical `.ppdmp` files.

| Scene | Files | Requested | Captured | Route state |
|---|---|---|---|---|
| Language Selection | frontend.{png,ppdmp} | 600 | 602 | ENGLISH highlighted; before CROSS at 700 |
| Title | title.{png,ppdmp} | 2650 | 2653 | "PRESS START BUTTON" (cursor shown); after START at 2400, before START at 2700 |
| Profile | profile.{png,ppdmp} | 2880 | 2882 | PROFILE, LOAD highlighted; before DOWN at 2900 |
| Main Menu | main_menu.{png,ppdmp} | 5640 | 5643 | MAIN MENU, SINGLE PLAYER highlighted, help text fully typed; after WARNING CROSS at 5250 |
| Vineta K start | vineta_k_start.{png,ppdmp} | 7154 | 7155.3 | first frame with the HUD (CURRENT 0.00.0, POS 8/8, LAP 1/3) fully faded in, ship on the grid; before READY |
| Boot log | boot-hle.log | | | boot to frame 5659 (Main Menu) on routes/frontend.txt with `--log` (HLE categories in docs/ppsspp.md) |
| Run report | ppsspp_run.json | | | the driver's JSON report of the capture run (flip times, framebuffer addresses, dump sizes) |

The Vineta K countdown has no digits: READY slides in from 7213, a blue ring fades in behind it from about 7220, and
the ring keeps spinning until GO! (green ring), when the timer starts. GO! was seen between 7241 and 7261 in a run
whose race presses were 150 frames earlier, which shifted every race event by exactly 150 frames, so it is at about
7391-7411 on these routes (not captured). With no "3" to pin, the reference is the brief's fallback: the first frame
with the HUD at CURRENT 0.00.0 and the grid. The HUD fades in over 7151-7155; 7155 is the first fully opaque frame.

## Regenerate

```
cd ~/dev/pure-recomp     # or a worktree with disc.iso linked
P=/opt/homebrew/bin/python3; R=tools/ppsspp/routes
$P tools/ppsspp/ppsspp_ctl.py run --pad-file $R/frontend.txt --pad-file $R/vineta_k_start.txt --until 7160 \
  --shot 600:ref/frontend.png --gedump 600:ref/frontend.ppdmp \
  --shot 2650:ref/title.png --gedump 2650:ref/title.ppdmp \
  --shot 2880:ref/profile.png --gedump 2880:ref/profile.ppdmp \
  --shot 5640:ref/main_menu.png --gedump 5640:ref/main_menu.ppdmp \
  --shot 7154:ref/vineta_k_start.png --gedump 7154:ref/vineta_k_start.ppdmp --report ref/ppsspp_run.json
$P tools/ppsspp/ppsspp_ctl.py run --pad-file $R/frontend.txt --until 5650 --log ref/boot-hle.log
```
About 2 minutes per run (real-time emulation). Check `ls ~/.config/ppsspp/PSP/SAVEDATA` first: only
`PPCD00001DLS001` may be there.

## SHA-256 of the 2026-10-05 captures

| File | SHA-256 |
|---|---|
| frontend.png | f1d2374d33a5b60d660e59a44953610b6687c1f21285140268308296b516fb2a |
| title.png | 725ae1c2a3317deb5755f77addbd2899e69f28cba9c92c9a88ca84df12bba878 |
| profile.png | f5c9bb2dec38af9bc45e53da838443c85b0ae2fe9c791223e9880ea133796e1f |
| main_menu.png | f1545c70b7b786dd9f4f176831d6b75a5cd56789ff9b781747d3a8d382c5c132 |
| vineta_k_start.png | 20f36ae28d57503e98027ea607314a68949ecc5d255ee04ce6d015ab849cb259 |
| frontend.ppdmp | ca978c97039380360e4b6f6c9d81f7da4d71a391e0beb9f9ef4f784672dab790 |
| title.ppdmp | 0e30e7ee835543382024ed7cc0742ec44a5c14832e9c11700f7355dd588ceba3 |
| profile.ppdmp | 5d28af107b969963dec0a8e53c9a6ed03d102996c6b30b7c92aec015ea6817f6 |
| main_menu.ppdmp | 39ff394b3f134f1ad1abd6c1952248a5213a3b39ee635b2bb13c62246d1f86ea |
| vineta_k_start.ppdmp | 1981e89408cfb554546d3d3196b6ab6a303f02719eaaac90313b8df775541e30 |

Save states are still not captured (`--savestate` needs the Accessibility permission, docs/ppsspp.md). Zone is,
since task 035 (below).

## Task 035 additions (2026-10-06)

The same PPSSPP, settings and memory stick as above (`PPCD00001DLS001` only; `save_yes.txt` writes a profile, which
was moved out afterwards). Routes in `tools/ppsspp/routes/`, each chained after `frontend.txt`; the comparisons with the
port and the suite rows they feed are in docs/history/fidelity.md ("PPSSPP references beyond the five") and
docs/verification.md.

A capture holds the CPU at a breakpoint while PPSSPP's file reads go on in real time, so a capture during a load ends
the load sooner in emulated time and moves every later frame. The race scenes below therefore come from runs with no
capture between the last menu press and the scene; where the table says "burst", the file is one frame of a
`--shots-every` run whose captures all come after the load, and that run is the command to repeat.

A burst names each file after the frame it asked for. A capture holds the game over two flips (the flip its
breakpoint stops at and the captured one), so in a 30-fps scene captures come at most every four vblanks, and a burst
that asks for more (every vblank, or every two) falls behind: the run's `frame N: captured frame M` lines give the
vblank each file shows. `tt_hud.png` and `fp_hud.png` (requested 7302, bursts every vblank from 7290) show vblank
7340, and `zone_hud.png` (requested 6668, from 6660) vblank 6694, as the re-run of 2026-10-06 below logged; the
burst K files (every two vblanks) likewise show later vblanks than their names, by an amount those runs' logs, not
kept, would give. The files themselves are what the suite compares with: only their labels were off.

| Scene | File | Route (after `frontend.txt`) | Requested | How |
|---|---|---|---|---|
| SINGLE PLAYER (SINGLE RACE highlighted) | single_player.{png,ppdmp} | vineta_k_start.txt | 5850 | run A |
| CLASS SELECTION (VECTOR) | class_select.{png,ppdmp} | vineta_k_start.txt | 6050 | run A |
| LEAGUE SELECTION (ALPHA) | league_select.{png,ppdmp} | vineta_k_start.txt | 6250 | run A |
| TRACK SELECTION (VINETA K) | track_select.{png,ppdmp} | vineta_k_start.txt | 6450 | run A |
| TEAM SELECTION (FEISAR) | team_select.{png,ppdmp} | vineta_k_start.txt | 6690 | run A |
| Time Trial TRACK SELECTION (records, medal times) | tt_track_select.{png,ppdmp} | time_trial_start.txt | 6650 | run B |
| Time Trial, first full-HUD frame, Vineta K | tt_hud.png | time_trial_start.txt | 7302 (captured 7340) | burst C |
| Free Play TRACK SELECTION | fp_track_select.{png,ppdmp} | free_play_start.txt | 6650 | run D |
| Free Play, first full-HUD frame, Vineta K | fp_hud.png | free_play_start.txt | 7302 (captured 7340) | burst E |
| TOURNAMENT SELECTION (ALPHA) | tournament_select.{png,ppdmp} | tournament_start.txt | 6450 | run F |
| Zone TRACK SELECTION (PRO TOZO) | zone_track_select.{png,ppdmp} | zone_start.txt | 6250 | run G |
| Zone 1, first frame with the HUD | zone_hud.png | zone_start.txt | 6668 (captured 6694) | burst H |
| OPTIONS, CONTROLS | options.{png,ppdmp}, controls.{png,ppdmp} | options_controls.txt | 6550, 6900 | run I |
| first full-HUD frame, Modesto Heights / Chenghou Project / Blue Ridge | modesto_heights_hud, chenghou_project_hud, blue_ridge_hud .{png,ppdmp} | vineta_k_start.txt + track_down1/2/3.txt | 7158 | run J (one per track) |
| first full-HUD frame, Sinucit, Citta Nuova, Sebenco Climb, Sol 2 | sinucit_hud.png ... sol_2_hud.png | unlock_all.txt + unlock_race_beta.txt [+ unlock_track_downN.txt] | 7662, 7664, 7670, 7652 | burst K |
| first full-HUD frame, Karbonis, Sagarmatha, Manor Top, Mandrashee | karbonis_hud.png ... mandrashee_hud.png | unlock_all.txt + unlock_race_classic.txt [+ unlock_track_downN.txt] | 7636, 7638, 7640, 7640 | burst K |
| the pause menu, Vineta K, about 450 frames after GO | pause.png | vineta_k_start.txt + vineta_k_hold_cross.txt + pause.txt | 7880 | burst L |
| the results panel after a three-lap Vineta K race | results_vineta_k.png | (`tools/fidelity_audit.py --ppsspp-race vineta_k`) | finish + 240 | the race driver |
| the system save dialog: the list, and Save completed | save_dialog.png, save_completed.png | save_yes.txt | 5200, 5400 | burst M |
| Zone 1's end panel (SHIP DESTROYED, TOTAL ZONES CLEAR 6), Cross held | zone_end.png | zone_start.txt | 11000 | run N |
| Zone 1's first zone change: the first frame with ZONE 2 and SCORE 800, the ship stopped at the first barrier, Cross held | zone_change.{png,ppdmp} | zone_start.txt | 7526 (captured 7528) | run O |

```
P=/opt/homebrew/bin/python3; R=tools/ppsspp/routes; C=tools/ppsspp/ppsspp_ctl.py
# run A
$P $C run --pad-file $R/frontend.txt --pad-file $R/vineta_k_start.txt --until 6700 \
  --shot 5850:ref/single_player.png --gedump 5850:ref/single_player.ppdmp --shot 6050:ref/class_select.png \
  --gedump 6050:ref/class_select.ppdmp --shot 6250:ref/league_select.png --gedump 6250:ref/league_select.ppdmp \
  --shot 6450:ref/track_select.png --gedump 6450:ref/track_select.ppdmp --shot 6690:ref/team_select.png \
  --gedump 6690:ref/team_select.ppdmp
# runs B, D, F, G, I: the same form, --until just past the last capture
$P $C run --pad-file $R/frontend.txt --pad-file $R/time_trial_start.txt --until 6660 --shot 6650:ref/tt_track_select.png --gedump 6650:ref/tt_track_select.ppdmp
$P $C run --pad-file $R/frontend.txt --pad-file $R/free_play_start.txt --until 6660 --shot 6650:ref/fp_track_select.png --gedump 6650:ref/fp_track_select.ppdmp
$P $C run --pad-file $R/frontend.txt --pad-file $R/tournament_start.txt --until 6460 --shot 6450:ref/tournament_select.png --gedump 6450:ref/tournament_select.ppdmp
$P $C run --pad-file $R/frontend.txt --pad-file $R/zone_start.txt --until 6260 --shot 6250:ref/zone_track_select.png --gedump 6250:ref/zone_track_select.ppdmp
$P $C run --pad-file $R/frontend.txt --pad-file $R/options_controls.txt --until 6910 --shot 6550:ref/options.png --gedump 6550:ref/options.ppdmp --shot 6900:ref/controls.png --gedump 6900:ref/controls.ppdmp
# bursts C, E, H: copy f07302.png (C, E) and f06668.png (H) to ref/
$P $C run --pad-file $R/frontend.txt --pad-file $R/time_trial_start.txt --until 7340 --shots-every 1 --shots-from 7290 --shots-dir out/ppsspp/ttfine
$P $C run --pad-file $R/frontend.txt --pad-file $R/free_play_start.txt --until 7340 --shots-every 1 --shots-from 7290 --shots-dir out/ppsspp/fpfine
$P $C run --pad-file $R/frontend.txt --pad-file $R/zone_start.txt --until 7350 --shots-every 1 --shots-from 6660 --shots-dir out/ppsspp/zonefine
# run J, N = 1, 2, 3 (modesto_heights, chenghou_project, blue_ridge)
$P $C run --pad-file $R/frontend.txt --pad-file $R/vineta_k_start.txt --pad-file $R/track_downN.txt --until 7160 --shot 7158:ref/NAME_hud.png --gedump 7158:ref/NAME_hud.ppdmp
# burst K, LEAGUE beta or classic, N empty or 1 to 3; copy the table's frame to ref/
$P $C run --pad-file $R/frontend.txt --pad-file $R/unlock_all.txt --pad-file $R/unlock_race_LEAGUE.txt [--pad-file $R/unlock_track_downN.txt] --until 7760 --shots-every 2 --shots-from 7580 --shots-dir out/ppsspp/hud_LEAGUE_N
# burst L (copy f07880.png), burst M (copy f05200.png and f05400.png; then move ~/.config/ppsspp/PSP/SAVEDATA/UCUS98612P0000 away)
$P $C run --pad-file $R/frontend.txt --pad-file $R/vineta_k_start.txt --pad-file $R/vineta_k_hold_cross.txt --pad-file $R/pause.txt --until 7960 --shots-every 4 --shots-from 7840 --shots-dir out/ppsspp/pause
$P $C run --pad-file $R/frontend.txt --pad-file $R/save_yes.txt --until 6200 --shots-every 10 --shots-from 5100 --shots-dir out/ppsspp/saveyes
# run N: sparse captures, none during the load
$P $C run --pad-file $R/frontend.txt --pad-file $R/zone_start.txt --until 11400 --shot 7500:out/ppsspp/z/f07500.png --shot 8500:out/ppsspp/z/f08500.png --shot 9500:out/ppsspp/z/f09500.png --shot 10500:out/ppsspp/z/f10500.png --shot 11000:ref/zone_end.png --shot 11300:out/ppsspp/z/f11300.png
# run O: one capture in the race, none before it (a burst every 4 vblanks from 7496 found the change: SCORE 299 and
# ZONE 1 at 7526, SCORE 801 and ZONE 2 at 7530)
$P $C run --pad-file $R/frontend.txt --pad-file $R/zone_start.txt --until 7540 --shot 7526:ref/zone_change.png --gedump 7526:ref/zone_change.ppdmp
# the results panel: out/fidelity/ppsspp/vineta_k/shots/r<finish+240>.png of
python3 tools/fidelity_audit.py --ppsspp-race vineta_k
```

The runs of 2026-10-06 (in the first worktree of task 035) gave these files. Each menu scene was captured twice, by
an exploration run with a capture every 10 vblanks and by its run above, with identical pixels; the Alpha HUD frames
of run J equal those of a burst from 7100 (Modesto Heights within 0.0001 at tol 0). The first worktree's captures went
with it, so the files the suite uses (runs A, B, D, F, G and bursts C, E, H) were made again in the task's second
worktree the same evening, 23:10 to 23:35, with the commands above: every PNG and GE dump came out byte-identical to
the hashes below. Run O (the zone change) comes from the second worktree and was run twice, with a byte-identical
PNG and GE dump.

Captures before a load do not move what follows: a run of `time_trial_start.txt` with a capture and GE dump at 6650
(TRACK SELECTION) and a shot at 7340, and one with the shot alone, captured the same flip (vblank 7342) with the same
pixels. The first worktree had found 0.98 of the pixels differing between a capture at 7302 and burst C's file, but
that file is vblank 7340, 38 vblanks later; the load-timing effect above rests on the two Zone runs of
docs/history/fidelity.md, whose captures came during the load.

| File | SHA-256 |
|---|---|
| single_player.png | e68e4eb5e8dcb7017fbce5b2afdcac96fd3913658beda9f2bceb83a8be8ecf74 |
| single_player.ppdmp | 950380bab54c93466ea4960e5d2b3d7d6f2ba96742048131dff696b95a216524 |
| class_select.png | 8f9fdbe2edf48f75a1189de97ef93d500ee5dfcba47b39647b62eaae3c91fd57 |
| class_select.ppdmp | 5c7d545a83c490b966b7eefabcf9b6f4ca250553cdcfd1b82008f50d4c869f6e |
| league_select.png | eacb2d0c5b06339694337c0116530c4923d387b7e612114f7c0c1dd6ee5c5e52 |
| league_select.ppdmp | ffd3118473a5ac8835934c5c6b7939dcfb827fc82c22dcc1799d92215ed99a35 |
| track_select.png | 278093d6aad921939d938b52254fa5c9ecfe62a895aa1bdc4f2bd23851438c26 |
| track_select.ppdmp | 66a54a8339e286038c2f31e254ccdd5667437e718d83f2d97062fd6c88b7756a |
| team_select.png | b68aabaf79231819f271527f394bb7a2a3de319802a0f849f17912960ace8708 |
| team_select.ppdmp | b88364cce153c6c6a74c99f1eb478d48d297806b269694aa0f30ac09ff0ca0f2 |
| tt_track_select.png | 56af652246db453946d56de49694d2c76a828310f329ccb719893dbaff3d6234 |
| tt_track_select.ppdmp | 7c9e6e7b64721b5f2dae1cecd4376386c507efa0baf0620014dfb8b191d7d227 |
| tt_hud.png | 5a305e3511d2af8a7c40a84d41cbd61dc26d3ea02eb2d06ea61a34324027e57f |
| fp_track_select.png | 07a06b497257fb5a7ad300d433659242f48e9f12d1c3446f103dca52a08786a0 |
| fp_track_select.ppdmp | 485f6e81903d06911746360e0a8b90c701f6518b446944b1dfbc096cf587e8a1 |
| fp_hud.png | 503f896cc0cb6f4d77a143eb6564f4c77efb32f267c858231ac3c0b8ddfcb1ef |
| tournament_select.png | 55eb4609dcb49a9daf9a81e3b112620d4d2a14d7b047ff30da026273514269d7 |
| tournament_select.ppdmp | ed3abebe15948676ebbc1fcfd04177aa6c19b184f5792ee61ee189e9201acab8 |
| zone_track_select.png | 613b348d823ce576f498773cc4e2d68be2d9ebc00dfbdbab3c4ae13debd59c1a |
| zone_track_select.ppdmp | 9023415a6feebf535f82675d938f3d749399626e1cc26dcb6cd439d7be27d20c |
| zone_hud.png | 93ac34c70d0ece2d04c0e4e9381090701c046d1416ab233468a7af653a357587 |
| options.png | feb0bc7efbd79cabb39380e2f74a07785d0464e32b6eded6d29a0acae7eafffc |
| options.ppdmp | fac59768c30c8f1fa9fdf63d8885984af2a2afb3cdfe46c6ae1dddcad8cc30a2 |
| controls.png | d4fa2c29c41556c9522faa76ea895091d635e3b2bcb16df99743135cbd596d2a |
| controls.ppdmp | b7ec53bdddb8d7f6a8ad306d79e29f1622118c26a816729423d7d34bb7936d5f |
| modesto_heights_hud.png | 01e4a61a5c4bde3222437fcf73832305b333fc2de1dee5aa80c105f0c1a1db8d |
| modesto_heights_hud.ppdmp | d3d2fe237f4d6d24a1e9b7cd58619af768a4f528f1e263e5008c542d7465fb1a |
| chenghou_project_hud.png | 46e4e5047bfa2eb679a4e247b9c544171f5f6874a662d63279715556138cbeef |
| chenghou_project_hud.ppdmp | 8d58d4f17b4c4908d70c5e2aa426cf64f5dd5e6a12d249e937729ae1aee37550 |
| blue_ridge_hud.png | f60cc14bd1c20ef78768a7d095773340748c5d7f00a720688726bc9dd4c0afe7 |
| blue_ridge_hud.ppdmp | e658d0ed70b541dd0ed171022869d86497a7e96c24c47db6331c2b6879b0577c |
| sinucit_hud.png | 305a41aa22601dadad54e02d18e2a40aae69f16cdfcd982a2c6e8979c194fb05 |
| citta_nuova_hud.png | ad335fc7027ed3c702dedbdbe683ffc38d19bfcae4f0f9eb6719e2b48df0d70f |
| sebenco_climb_hud.png | 2dedf676d8f30fe66114f8b2228c6db6c0ddd78bb3f028c294617cf6ac81d404 |
| sol_2_hud.png | cfb6f8f1efdeccd4e130f670622c8a2671155417e1620a61e9a55999d2de9bae |
| karbonis_hud.png | ac6a02f8e4f790f3b00d20dfba046cc3815cecf607f9ca58ff2d831a2a5bc95b |
| sagarmatha_hud.png | 20be274dc9d13d215a13d8c34a5a2418853231e4c77c9675257eaa84a96a551c |
| manor_top_hud.png | 3bbd61708781c6fac126d57e758c094ca5ba523285a8f460f7073fc0f4564e96 |
| mandrashee_hud.png | 3b55ddcf0ff78f3668764ddffcfbdf84821107ddb53bde51155c9e420a53779f |
| pause.png | 34c9ac07c56df24638d226ec101351625680298aebb12d11a5239a43b9ecdedd |
| results_vineta_k.png | d8567f3654d8397d27876e19e91e8570d0b7d6588c1f1e70a452d9e48e16b940 |
| save_dialog.png | b1664e284c5e5795dc86ad32ebac44bf271fb2df198779e80e5290c5ebb539b0 |
| save_completed.png | 536f89bc31f5e753a6a988a5fca5924d76ffada82316816ae7775561afaa660d |
| zone_end.png | a20fcb80d2823f818a9d915ca6c38b972aaac56eb5c58c40b5e46a559374425f |
| zone_change.png | a192682e6ddf59f033d4797d0ab848eff2d0f2efecce3b7e17235cb0475a7bed |
| zone_change.ppdmp | 985cd7a5224f2a3e06eea5ceca140aed48cf7d6a8a9286eae9e6015a236b5f2b |

## Task 043 addition (2026-10-07): the Free Play pause audio dump

`audio/free_play_pause.wav` is PPSSPP's own audio dump (`--dump-audio`, docs/ppsspp.md "Audio dumps": the sceAudio
channels mixed and clamped, 44.1 kHz stereo on emulated time from boot) of task 041's Free Play pause route: the ship
left on Vineta K's grid past the race music's first track change, START at vblank 28800 (480.479 s), then END
SESSION. 495.5 s, 87,399,468 bytes. `tools/sas_reverb_check.sh` compares the port's sound after the pause with it
(docs/fidelity.md, "The SAS reverb check"). Same PPSSPP and memory stick as above; the hardware renderer, which
does not change an emulated-time dump. About 8 minutes:

```
python3 tools/ppsspp/ppsspp_ctl.py run --pad-file tools/ppsspp/routes/frontend.txt \
  --pad-file tools/ppsspp/routes/free_play_start.txt --pad-file tools/ppsspp/routes/free_play_idle_end.txt \
  --until 29700 --renderer hardware --dump-audio ref/audio/free_play_pause.wav
```

| File | SHA-256 |
|---|---|
| audio/free_play_pause.wav | 6487ea241bb0608d0757683bbabd573e1f5b06830769d9f00f1e7a4b89bb0b70 |

## Saves (task 045, 2026-10-07)

`ref/saves/` holds the save folders `tools/save_interchange.sh` uses (git-ignored like the rest of `ref/`):

- `ref/saves/ppsspp/UCUS98612P0000/`: PPSSPP's profile NAME0000 / AAA, written 2026-10-07 09:58 by PPSSPP 1.20.4
  through the driver's routes `frontend.txt` + `save_yes.txt` + `save_dialog.txt` (YES on SAVE PROFILE; the CROSS at
  5250 picks NEW DATA, P0000, in PPSSPP's save dialog; CIRCLE at 5400 closes "Save completed."; MAIN MENU by 5540),
  then moved out of PPSSPP's memory stick. Remake it with `tools/save_interchange.sh --make-ppsspp-save` (the stick
  must hold no `UCUS98612P*`). An earlier run of the same routes without `save_dialog.txt` gave a `PROFILE.BIN` whose
  decrypted contents are identical.
- `ref/saves/ppsspp/PPCD00001DLS001/`: PPSSPP's first-boot autosave (the online system's info), copied from its
  memory stick, where trial 6 of task 006 wrote it on 2026-10-05.
- `ref/saves/port-plain/UCUS98612P0000/`: a plain save written by the port before task 045 (batch/m2 at aa9128a,
  `config/pad_scripts/main_menu.txt` headless on an empty stick, 2026-10-07 09:54): the kind of save every port build
  wrote until then (SAVEDATA_PARAMS flag 0, `SAVEDATA_FILE_LIST` empty, `PROFILE.BIN` 41570 bytes plain).

| File | SHA-256 |
|---|---|
| ppsspp/UCUS98612P0000/ICON0.PNG | 78cdec5c24671561c490a8096d26fb725794c42a31e3ffdcad1e6dc51d28c7e0 |
| ppsspp/UCUS98612P0000/ICON1.PMF | ae2ba722b69a0abfd8b42cea909095c045599d7b2055797f0f851f578da21fba |
| ppsspp/UCUS98612P0000/PARAM.SFO | 162c45976f78db8aa8e1ce11598eb5fd0e5074926e06b5a7e5eba26a50c6396b |
| ppsspp/UCUS98612P0000/PIC1.PNG | 430218db46278245ae67a971a7f505fbbad2a1a270b80bf52b46cc9c3cb7df28 |
| ppsspp/UCUS98612P0000/PROFILE.BIN | e4bae8420dccaa5ca82cdefa08ea626d2d49157bb99ca361044c6f4ad94edb8f |
| ppsspp/UCUS98612P0000/SND0.AT3 | c558e377092cabc09b6e388fdc3734d4965fb3eb925c1cb46dc3266df80ac5ee |
| ppsspp/PPCD00001DLS001/DATA1.BIN | 682bd939bbfd9654d782825c67521e88cdf3dea47708325d41f5742b43e4b26d |
| ppsspp/PPCD00001DLS001/DATA2.BIN | 1f6944fb2a63d3708ac955adc1bfe3b3930d1d403c7b390c206ba83a2a239040 |
| ppsspp/PPCD00001DLS001/ICON0.PNG | 1f9ecb8f0b5ddeef4f3a59c97555d172e2777fc6710b0778c230a0ba7e4edbac |
| ppsspp/PPCD00001DLS001/PARAM.SFO | 4c7fed5aa76d3ecf76c8d817e8cfb26e5665e6f0e19da257de55a294cf372abc |
| port-plain/UCUS98612P0000/ICON0.PNG | 78cdec5c24671561c490a8096d26fb725794c42a31e3ffdcad1e6dc51d28c7e0 |
| port-plain/UCUS98612P0000/ICON1.PMF | ae2ba722b69a0abfd8b42cea909095c045599d7b2055797f0f851f578da21fba |
| port-plain/UCUS98612P0000/PARAM.SFO | 2fa79983f704c645d419c4d5219d2b50cebaaeb81af31a64bb6010d19ae7bed0 |
| port-plain/UCUS98612P0000/PIC1.PNG | 430218db46278245ae67a971a7f505fbbad2a1a270b80bf52b46cc9c3cb7df28 |
| port-plain/UCUS98612P0000/PROFILE.BIN | a12efe59b001d5ef6a3c7be4564f9c5fc5797ba93cdde3c9c38f10dcb0371b2a |
| port-plain/UCUS98612P0000/SND0.AT3 | c558e377092cabc09b6e388fdc3734d4965fb3eb925c1cb46dc3266df80ac5ee |

Copy them into another worktree with `cp -Rp ~/dev/pure-recomp/ref/saves ref/` (the main checkout keeps the set).

## Task 044 additions (2026-10-07): the scorecard's references

`tools/scorecard.py --refresh-references [CATEGORY]` takes the PPSSPP side of the accuracy scorecard (docs/scorecard.md,
docs/fidelity.md "The accuracy scorecard") and keeps it under `ref/scorecard/`, git-ignored like every capture
here. It lists each file it made, with its size, SHA-256 and the command that made it, in
`ref/scorecard/manifest.json` and in the table below, which it rewrites between the two markers. Same PPSSPP, settings
and memory stick as above (`PPCD00001DLS001` only; the tool waits while PPSSPP runs for someone else or while its
stick holds a profile save, and moves its own save off the stick). The hardware renderer throughout: nothing here is
read from VRAM.

| Directory | Files | How |
|---|---|---|
| `scorecard/trajectories/` | `TRACK.csv` for the 12 circuits, `TRACK.flips.txt`, and `vineta_k.run2.*` | a Single Race at Vector on each circuit from the routes of task 035 (`frontend.txt` + `vineta_k_start.txt` [+ `track_downN.txt`] for Alpha, `frontend.txt` + `unlock_all.txt` + `unlock_race_LEAGUE.txt` [+ `unlock_track_downN.txt`] for Beta and Classic), Cross held from the first READY frame (58 vblanks after the first full-HUD frame) to the end. Every race record is sampled through the debugger's `memory.read` while the CPU runs, as `tools/pp_lines.py` samples them, each block read twice and kept when the two reads agree, until the player's clock reaches 25 s (65 s on the three audio circuits); the CSV has pp_lines' columns. A log-only breakpoint on `sceDisplaySetFrameBuf` gives every flip's emulated time and the player's clock (`.flips.txt`, from vblank 5000). `vineta_k.run2` is a second run of Vineta K, the AI ships' determinism check. About 2.5 to 3.5 minutes a circuit |
| `scorecard/audio/` | `vineta_k.wav`, `sinucit.wav`, `sagarmatha.wav`, `main_menu.wav` | PPSSPP's audio dump (`--dump-audio`) of the three circuits' runs above, and of `frontend.txt` + `main_menu_music.txt` to vblank 9900 (MAIN MENU's music with L pressed every 20 s, which keeps the attract demo away and makes no sound) |
| `scorecard/saves/UCUS98612P0000/` | the six files PPSSPP's save of the profile wrote | `frontend.txt` + `save_yes.txt` to vblank 6200: YES on SAVE PROFILE, the system dialog's first slot (frontend.txt's Cross at 5250), "Save completed."; the folder is moved here from PPSSPP's memory stick |
| `scorecard/timing/ppsspp/vineta_k/` | `summary.json`, `ppsspp.log` | `tools/fidelity_audit.py --ppsspp-race vineta_k --out ref/scorecard/timing`: the sweep's follower drives three laps of Vineta K in PPSSPP; the summary lists the two-vblank stretches and the log every flip (the race load); its shots and samples are removed |

<!-- scorecard references: begin (written by tools/scorecard.py --refresh-references) -->
| File (under ref/) | Bytes | SHA-256 | Made | How |
|---|---|---|---|---|
| scorecard/audio/main_menu.wav | 29128748 | 4d362bcd4206f19094fefb211b9063ae3e5896de1b4eb048861fea81843f6389 | 2026-10-08 11:13 | PPSSPP frontend.txt + main_menu_music.txt to vblank 9900; its audio dump |
| scorecard/audio/sagarmatha.wav | 37425152 | b26de19dde7a5279f93a5b15036ee61d684f2ef7b0c863acee2eb1fcc7d06a76 | 2026-10-08 10:58 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt + unlock_track_down1.txt, Cross from vblank 7696, race records to 65 s of race clock; PPSSPP's audio dump |
| scorecard/audio/sinucit.wav | 37519360 | b633e80e0face1e17dba8be6144632b550421809d1edc82128b21cba12a5b14b | 2026-10-08 10:36 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt, Cross from vblank 7720, race records to 65 s of race clock; PPSSPP's audio dump |
| scorecard/audio/vineta_k.wav | 36057088 | ef2f1b539af8b420d4f84585912e5653c51f42b2dee4e32066a8e10fc5d6fded | 2026-10-08 10:19 | PPSSPP frontend.txt + vineta_k_start.txt, Cross from vblank 7213, race records to 65 s of race clock; PPSSPP's audio dump |
| scorecard/saves/UCUS98612P0000/ICON0.PNG | 6742 | 78cdec5c24671561c490a8096d26fb725794c42a31e3ffdcad1e6dc51d28c7e0 | 2026-10-08 11:15 | PPSSPP frontend.txt + save_yes.txt to vblank 6200 (YES on SAVE PROFILE, the first slot) |
| scorecard/saves/UCUS98612P0000/ICON1.PMF | 51200 | ae2ba722b69a0abfd8b42cea909095c045599d7b2055797f0f851f578da21fba | 2026-10-08 11:15 | PPSSPP frontend.txt + save_yes.txt to vblank 6200 (YES on SAVE PROFILE, the first slot) |
| scorecard/saves/UCUS98612P0000/PARAM.SFO | 4912 | 188f12dc292e6bc5c4b0c66ab8f1ea542d5567a78ce9dfa0b0f9f834731bcad1 | 2026-10-08 11:15 | PPSSPP frontend.txt + save_yes.txt to vblank 6200 (YES on SAVE PROFILE, the first slot) |
| scorecard/saves/UCUS98612P0000/PIC1.PNG | 172944 | 430218db46278245ae67a971a7f505fbbad2a1a270b80bf52b46cc9c3cb7df28 | 2026-10-08 11:15 | PPSSPP frontend.txt + save_yes.txt to vblank 6200 (YES on SAVE PROFILE, the first slot) |
| scorecard/saves/UCUS98612P0000/PROFILE.BIN | 41586 | 1eddea1232511776b77a4c502dfeed7da9cac061e53ebd3e543f01680d911a4d | 2026-10-08 11:15 | PPSSPP frontend.txt + save_yes.txt to vblank 6200 (YES on SAVE PROFILE, the first slot) |
| scorecard/saves/UCUS98612P0000/SND0.AT3 | 97604 | c558e377092cabc09b6e388fdc3734d4965fb3eb925c1cb46dc3266df80ac5ee | 2026-10-08 11:15 | PPSSPP frontend.txt + save_yes.txt to vblank 6200 (YES on SAVE PROFILE, the first slot) |
| scorecard/timing/ppsspp/vineta_k/ppsspp.log | 54750494 | 0dbf09f29878f902f6f4ec233e6c7ea0871623163a10e7ddd2877ed48c81e335 | 2026-10-08 11:24 | tools/fidelity_audit.py --ppsspp-race vineta_k --out ref/scorecard/timing |
| scorecard/timing/ppsspp/vineta_k/summary.json | 1517 | 0c38563a2969d0c5498918bfb3adff0705f5d950feb3b3dc5fdafac20a141aef | 2026-10-08 11:24 | tools/fidelity_audit.py --ppsspp-race vineta_k --out ref/scorecard/timing |
| scorecard/trajectories/blue_ridge.csv | 865176 | 0b129ee30c921ad4b65263c106f3cfb03fe9bc1076cfd113adca7173fc9ce78d | 2026-10-08 10:30 | PPSSPP frontend.txt + vineta_k_start.txt + track_down3.txt, Cross from vblank 7216, race records to 25 s of race clock |
| scorecard/trajectories/blue_ridge.flips.txt | 59532 | 2b2409f266ad11d8169577580ffb3d8b7cf35e276a7505f59e21a3c7e2ddaaed | 2026-10-08 10:30 | PPSSPP frontend.txt + vineta_k_start.txt + track_down3.txt, Cross from vblank 7216, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/chenghou_project.csv | 879231 | 288049bda726efe38fc03c9a74251ebeaf77c387137bf6b9c364bd13d23dc40e | 2026-10-08 10:27 | PPSSPP frontend.txt + vineta_k_start.txt + track_down2.txt, Cross from vblank 7216, race records to 25 s of race clock |
| scorecard/trajectories/chenghou_project.flips.txt | 59028 | 9e4ffd3d812fd2b330f572e1f29d809f1fd4084cda7d9ada64efe92c805066b5 | 2026-10-08 10:27 | PPSSPP frontend.txt + vineta_k_start.txt + track_down2.txt, Cross from vblank 7216, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/citta_nuova.csv | 886395 | 3a325ebaf19557700dda3b0b5d8685fd905c4e071a3b6b01da51fa8fb27c232b | 2026-10-08 10:40 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt + unlock_track_down1.txt, Cross from vblank 7722, race records to 25 s of race clock |
| scorecard/trajectories/citta_nuova.flips.txt | 64572 | 245e91e947d118f810f88c84cbd0f110fb5abbfde0cd1e053fd6a52854f72cd8 | 2026-10-08 10:40 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt + unlock_track_down1.txt, Cross from vblank 7722, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/karbonis.csv | 898548 | 55a06190e2cdac815508b0b72f89284da0b311e7cc56b5bc6ed463ce340cad39 | 2026-10-08 10:52 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt, Cross from vblank 7694, race records to 25 s of race clock |
| scorecard/trajectories/karbonis.flips.txt | 64292 | 4187845de2ab217d9910d42f194eab25c447ac0c704b513d967456c18f0a8845 | 2026-10-08 10:52 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt, Cross from vblank 7694, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/mandrashee.csv | 898008 | 2f126d8284fcf358508dc218e43add0d00f842bec38ad621aa70169e8503b8af | 2026-10-08 11:06 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt + unlock_track_down3.txt, Cross from vblank 7698, race records to 25 s of race clock |
| scorecard/trajectories/mandrashee.flips.txt | 64311 | 376d7069f93fa92ca26898b04783ac10ccd6cc2a84f91a901d8a4d2b78b71314 | 2026-10-08 11:06 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt + unlock_track_down3.txt, Cross from vblank 7698, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/manor_top.csv | 883569 | 42212548c181b3ea0ae6d8c74562e4094da9b586105f869d9326c44ab8a0d110 | 2026-10-08 11:02 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt + unlock_track_down2.txt, Cross from vblank 7698, race records to 25 s of race clock |
| scorecard/trajectories/manor_top.flips.txt | 64332 | 029550ca36257808353a7a47e9174061a0a1cec2067b88380feeee30baa2a500 | 2026-10-08 11:02 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt + unlock_track_down2.txt, Cross from vblank 7698, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/modesto_heights.csv | 802148 | f6a092f9587f6623797632677512ff41df849a367120a15771b819b13862d050 | 2026-10-08 10:23 | PPSSPP frontend.txt + vineta_k_start.txt + track_down1.txt, Cross from vblank 7216, race records to 25 s of race clock |
| scorecard/trajectories/modesto_heights.flips.txt | 59533 | af8208d802967dc617355aea8fa50e5e782b42114811c9a1719fd2e3739cb76a | 2026-10-08 10:23 | PPSSPP frontend.txt + vineta_k_start.txt + track_down1.txt, Cross from vblank 7216, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/sagarmatha.csv | 2298435 | e73232e88efb436923c5edab26bb88e1f4c954f32f06b18b208692b295fe4721 | 2026-10-08 10:58 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt + unlock_track_down1.txt, Cross from vblank 7696, race records to 65 s of race clock |
| scorecard/trajectories/sagarmatha.flips.txt | 134053 | 4477336abe648e8201a37a0bffe8ccf04c3ff7481558b32135e5370c4de41daa | 2026-10-08 10:58 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt + unlock_track_down1.txt, Cross from vblank 7696, race records to 65 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/sebenco_climb.csv | 894073 | c4a54f4ab0e16035d6680c8a3d1adcda121726947d023467e8fb3186b61f9211 | 2026-10-08 10:44 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt + unlock_track_down2.txt, Cross from vblank 7728, race records to 25 s of race clock |
| scorecard/trajectories/sebenco_climb.flips.txt | 64695 | d5fab3df6645fec62a0ee212d90ef1e0ebbcbd98debe6529657bc77b8d2e33d4 | 2026-10-08 10:44 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt + unlock_track_down2.txt, Cross from vblank 7728, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/sinucit.csv | 2347427 | a5764f5ab46e3dc124632429485bedb583293d82a7597115c6c60cbfbc1d3111 | 2026-10-08 10:36 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt, Cross from vblank 7720, race records to 65 s of race clock |
| scorecard/trajectories/sinucit.flips.txt | 134104 | 9bbb7ef56eea1bdc77edc665240740acbca72dfcf82c814c91860aba533e35a4 | 2026-10-08 10:36 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt, Cross from vblank 7720, race records to 65 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/sol_2.csv | 885726 | bdd1bbc5c84141cbd363ddffd6df2f195905f6c6428416edbf39a32ac8d464ab | 2026-10-08 10:48 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt + unlock_track_down3.txt, Cross from vblank 7710, race records to 25 s of race clock |
| scorecard/trajectories/sol_2.flips.txt | 64453 | 819ef95f98c06444afedc36782f79f2032fc511c2df40e78e2830d57ce1e21fb | 2026-10-08 10:48 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt + unlock_track_down3.txt, Cross from vblank 7710, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/vineta_k.csv | 2324810 | ff891d5eda6297821ce0cef26066e33e28bf9553dd4b618bf7a76ea429686fb6 | 2026-10-08 10:19 | PPSSPP frontend.txt + vineta_k_start.txt, Cross from vblank 7213, race records to 65 s of race clock |
| scorecard/trajectories/vineta_k.flips.txt | 129423 | 65e96ec5a061aef851e5b2bda2f192e681e3eebc208a14bc779f042eef9a3e5e | 2026-10-08 10:19 | PPSSPP frontend.txt + vineta_k_start.txt, Cross from vblank 7213, race records to 65 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/vineta_k.run2.csv | 904330 | 2dacf66fb918aa395dc505660aba8ddc555b627fa2421f2c7e7df5f46efb5507 | 2026-10-08 11:10 | PPSSPP, Vineta K again: the AI ships' determinism check |
| scorecard/trajectories/vineta_k.run2.flips.txt | 59514 | 380e365aca7c9f3197bb3a7496d041cc99fa7faba88222005de59ef2205964e4 | 2026-10-08 11:10 | the second run's flips |
<!-- scorecard references: end -->

## Task 047 (2026-10-07): PPSSPP's VFPU samples

`ref/vfpu/` (docs/fidelity.md, "The VFPU dot-product check"; docs/fidelity.md, difference 13): PPSSPP 1.20.4's
operands and results at the game's VFPU dot-product and transcendental instructions over the scorecard's Vineta K race
(`frontend.txt` + `vineta_k_start.txt`, Cross from vblank 7213), from READY to 12 s of race clock. Each set directory
holds `sites.json` (the sites, their lanes, prefixes and rows, the run's CPU core and every ship's end offset from
`scorecard/trajectories/vineta_k.csv`), one `<ADDR>.csv` a site (PPSSPP's bits) and one `<ADDR>.port.csv` (the port's
results for the same operands, from `tools/vfpu_probe.py port`, which change with the codegen). A digest is the
SHA-256 of `shasum -a 256` over the set's files in name order (`cd ref/vfpu/jit && ls *.csv | grep -v port | sort |
xargs shasum -a 256 | shasum -a 256`).

```
P=/opt/homebrew/bin/python3
$P tools/vfpu_probe.py cover --seconds 3                                   # coverage.csv, coverage.json; 2.5 min
$P tools/vfpu_probe.py sample --out ref/vfpu/jit --sites all --cap 5000 --seconds 12          # 3.5 min
$P tools/vfpu_probe.py sample --out ref/vfpu/interp --cpu-core 0 --cap 1500 --seconds 12 --sites \
  089196B8,08926E08,08823DB8,08930074,08929A74,0891B11C,0882375C,08827504,088AE970,08887C04,08893674,08886A70,\
088AF05C,08934758,088F1144,088AF030,0886A37C,088C9F88,088F11A0,088936CC,08927230,08929A6C,08827570,088437E8,08824BB4,\
089196BC,08930078                                                           # 22 min (the interpreter is stepped)
$P tools/vfpu_probe.py port ref/vfpu/jit && $P tools/vfpu_probe.py port ref/vfpu/interp
```

| File or set | Size | SHA-256 | Made |
|---|---|---|---|
| vfpu/coverage.csv | 26382 | 8d403fb525abff6a837b7350779cb47d864bf9b3c7d922a6b48ff8a2e5d782ea | 2026-10-07 14:16, JIT, 711 sites, 205 run to 3.2 s of race clock |
| vfpu/coverage.json | 411 | 806f48673cff16b1a655128bec43e76a66f6ac92bbf3782c739c6ced89a0bc12 | the same run |
| vfpu/jit/sites.json | 114424 | 6a12c13395db313b773ff46e9b5713224d9d9bc0d2252ffe328ff0d8d516f436 | 2026-10-07 14:44, CPU core 1 (JIT), 195 sites, 812229 rows |
| vfpu/jit/*.csv (195, not port) | 67855107 | digest d6c7e4c6ef9d8e25c40e6244e7f3c6000d364293418d7111cdb4a6630b8ecb5b | the same run |
| vfpu/jit/*.port.csv (195) | | digest aafa9b5cc955d05136f9d6986e13082bda4d2e70434718232964fc6b1771e1d5 | `port`, on the corpus in generated/ of 2026-10-07 (before the dot-product change) |
| vfpu/interp/sites.json | 19713 | 9fd78a712681861736107bfdcb95bee0177074a59b2c2036264bd21eb684803b | 2026-10-07 15:15, CPU core 0 (interpreter), 27 sites, 60086 rows |
| vfpu/interp/*.csv (27, not port) | 7796062 | digest 01b2d42218c16fe243f455b56290e55521b385b4099409ed0dc9051c08c4121a | the same run |
| vfpu/interp/*.port.csv (27) | | digest a05aea6f8f3604dd5f0b4ee39c6082540dc15e39b80e8a71624dfb0d0aac530e | `port`, on the corpus in generated/ of 2026-10-07 (before the dot-product change) |

PPSSPP's memory stick held `PPCD00001DLS001` only, before and after every run; each run's ini was put back (CPU core
1, the machine's setting, after the interpreter's).

## Task 048 (2026-10-07): PPSSPP's samples of the other kinds

Three more sets under `ref/vfpu/jit/` (docs/fidelity.md, "The other kinds"; docs/fidelity.md, difference 13), each
with its own coverage files: PPSSPP 1.20.4's JIT on the scorecard's reference routes. `048_vineta_k` and
`048_karbonis`: every execution from READY to 13 s of race clock of every `vcrsp`, `vfad` and `vmscl` site with 50 or
more hits (no `vcrs`, `vqmul`, `vavg` or `vrot` ran). `048_karbonis_dot`: every execution of every dot-product and
transcendental site (711) from 6.0 to 7.0 s of race clock, the stretch before the port's Karbonis player first parts
from PPSSPP's (its 1422 breakpoints move PPSSPP's AI by up to 31 m and its player by 4 cm at 7.6 s; each row is still
one execution). The port files: `<ADDR>.port.ppsspp.csv` and `.port.psp.csv` (the corpus in generated/ of 2026-10-07,
with task 047's rounding, under each mode), `.port.pre0020.csv` (the header hunk of that rounding reversed,
`--fp-contract on`: the corpus before it; the file names keep the old patch number, 0020, now part of patch
0009-vfpu-rounding), `.port.candidate.<mode>.csv` (the header of docs/tasks/048's Result, in a copy). A digest is the SHA-256
of `shasum -a 256` over the files in name order (`ls [0-9A-F]*.csv | grep -v port | sort | xargs shasum -a 256 |
shasum -a 256` for PPSSPP's rows; `ls *.port.ppsspp.csv | sort | ...` for a port file set).

```
P=/opt/homebrew/bin/python3; K=vcrs,vcrsp,vqmul,vfad,vavg,vrot,vmscl
$P tools/vfpu_probe.py cover --track vineta_k --kinds $K --seconds 13 --out ref/vfpu/jit/048_vineta_k     # 2.5 min
$P tools/vfpu_probe.py sample --track vineta_k --out ref/vfpu/jit/048_vineta_k --sites all --cap 0 --seconds 13   # 4 min
$P tools/vfpu_probe.py cover --track karbonis --kinds $K --seconds 13 --out ref/vfpu/jit/048_karbonis     # 2.5 min
$P tools/vfpu_probe.py sample --track karbonis --out ref/vfpu/jit/048_karbonis --sites all --cap 0 --seconds 13   # 3.5 min
$P tools/vfpu_probe.py sample --track karbonis --out ref/vfpu/jit/048_karbonis_dot --window 6.0,7.0 --seconds 7.2 \
  --sites "$($P tools/vfpu_probe.py scan --kinds vdot,vhdp,vmmul,vtfm,vrcp,vrsq,vsin,vcos,vsqrt,vexp2,vlog2,vasin,vnrcp,vnsin,vrexp2 \
  | awk '/^0x/ {print substr($1,3)}' | paste -sd, -)"                                                     # 3 min
for s in 048_vineta_k 048_karbonis 048_karbonis_dot; do $P tools/vfpu_probe.py port ref/vfpu/jit/$s --modes ppsspp,psp; done
$P tools/vfpu_probe.py port ref/vfpu/jit --modes ppsspp,psp                                             # task 047's set
```

| File or set | Size | SHA-256 | Made |
|---|---|---|---|
| vfpu/jit/048_vineta_k/coverage.csv | 7033 | 40653fd77ecdc1944c748c405a44247bc9d5803fc3ed2beb2c23388818106454 | 2026-10-07 16:24, 197 sites, 101 run to 13.1 s |
| vfpu/jit/048_vineta_k/coverage.json | 622 | b2fb44788e8a5054d0dfbf3e1c045807e532de883f95a427d47a255ed13e025b | the same run |
| vfpu/jit/048_vineta_k/sites.json | 37525 | 76a8084eb0115b6fb231eba8fc7b47b31497aaed32337d7341edcf9eccab8af6 | 2026-10-07 16:28, 65 sites, 905848 rows |
| vfpu/jit/048_vineta_k/[0-9A-F]*.csv (65) | 80546081 | digest 1ec8c0035d87a5c8c3fdc898e4bd6d352471b71e7e8213ff70fda85eeed57ff1 | the same run |
| vfpu/jit/048_vineta_k/*.port.ppsspp.csv (65) | | digest c5bdc9be6367dcc6a0f48862bc150045072bcde5834e62f44315ce8ccf6bb0ea | `port --modes ppsspp,psp` |
| vfpu/jit/048_vineta_k/*.port.psp.csv (65) | | digest 8bfc28c1a2f5c15b434ae4a9fdae988144173a294ebfb3fdac6aaa86b1aa9301 | the same |
| vfpu/jit/048_karbonis/coverage.csv | 7012 | b73f1ad30148b4d25a8c7d9c9a316b18a7734551f26be3a14b3fb6391e8a13a9 | 2026-10-07 16:13, 197 sites, 72 run to 13.2 s |
| vfpu/jit/048_karbonis/coverage.json | 646 | 9a6e501bd5ce7a7b1cfebfa022b1a0d3933bae5405925a07d0b7b2f590f302da | the same run |
| vfpu/jit/048_karbonis/sites.json | 36214 | 91fd976520b05dc7fe344ed8ab938c95329b2ed860717c4ff0d2c67a258f32f1 | 2026-10-07 16:18, 62 sites, 869416 rows |
| vfpu/jit/048_karbonis/[0-9A-F]*.csv (62) | 64516343 | digest 1254af558e16f3cfef113626bf0da171c7980cfd9719bb8156da8783c0f35938 | the same run |
| vfpu/jit/048_karbonis/*.port.ppsspp.csv (62) | | digest 25e8196e219d5a423df3015941a0a41c715660a01f0a3de6f349fe0162f1bb9c | `port --modes ppsspp,psp` |
| vfpu/jit/048_karbonis/*.port.psp.csv (62) | | digest 35a76d0e2a10ae87505670dfa96905399132768dad0f6a7426d5f3429d0da6dc | the same |
| vfpu/jit/048_karbonis/*.port.pre0020.csv (62) | | digest de9390e29042b180244f6c89db084ea2da3426db41d5092283667a3f7bc866ae | the corpus before task 047's rounding |
| vfpu/jit/048_karbonis/*.port.candidate.ppsspp.csv (62) | | digest a82012adddfc02599edf8a1aa52775031ab7404dd23203310e5407074ef255ab | the Result's header, test mode |
| vfpu/jit/048_karbonis/*.port.candidate.psp.csv (62) | | digest db53e942421d8ebf24fa70c85e888629a9e5081c1cb49ed1eb451257a3978dd1 | the same, default mode |
| vfpu/jit/048_karbonis_dot/sites.json | 428367 | d4f4f768626c2cca3885f6af6e7e5c4249d772c0e1e51aee0f36e25e49b8aba2 | 2026-10-07 16:31, 711 sites, 213 with rows, 259370 rows |
| vfpu/jit/048_karbonis_dot/[0-9A-F]*.csv (711) | 24213988 | digest 8f092e00fd6eaa503eb015f8dc4505d38f56339820fef8d6cf80aa688aa2ef25 | the same run |
| vfpu/jit/048_karbonis_dot/*.port.ppsspp.csv (710) | | digest c44da6d3c73cc7ad27873cb21f7511b492ad49658ff479d68ecd9348c4124932 | `port --modes ppsspp,psp` (0x08887FFC, no rows, has no block of its own) |
| vfpu/jit/*.port.ppsspp.csv (195) | | digest d9b709d8680af433ec6108553d1fe7054c4cc1bc74dfb7acdbc97fa3f1c381e5 | task 047's set, `port --modes ppsspp,psp` on the corpus with task 047's rounding |
| vfpu/jit/*.port.psp.csv (195) | | digest 45f59fda32d05d4df57c297883661808861c60fc9a6ac40c6c2711bfe73760b7 | the same |

The Vineta K set's `.port.pre0020.csv` and `.port.candidate.<mode>.csv` are made the same way as Karbonis'. PPSSPP's
memory stick held `PPCD00001DLS001` only, before and after every run; every run's ini was put back (CPU core 1).

## Task 055 (2026-10-08): the Windows retake of the VFPU samples

`ref/vfpu/` was retaken on Erik's Windows machine with PPSSPP 1.20.4 for Windows (x64 JIT on CPU core 1; the
interpreter run on core 0 used the Mac's 27 sites), because the Apple Silicon JIT's rounding does not transfer
(docs/windows.md, docs/fidelity.md difference 13). `vfpu_model.py --check` exits 1 on these sets as predicted:
the x64 JIT does not follow the Apple JIT's dot-product rule (per-instruction agreement 77.7% to 100%). The
port's test mode still reproduces the Mac's Apple-JIT samples on every row, so the port's x64 rounding is the
arm64 rounding. The Mac's sets of task 047 (the table above) are preserved in `ref/mac-2026-10-07/`.

| File or set | Size | SHA-256 | Made |
|---|---|---|---|
| vfpu/coverage.csv | 33289 | 56bbab359395ccb90100677bdbc5fd470059e1d3890f67c33848858637887858 | 2026-10-08, JIT, 251 of 908 sites executed, 1748277 hits |
| vfpu/jit/sites.json | 149688 | 241dcd4266ee8df365409f588bc5d9d1f2889a5ed62dad7b621725ce7622f6fa | 2026-10-08, CPU core 1 (x64 JIT), 243 sites |
| vfpu/jit/*.csv (243, not port) | | digest 0d4202c837954e4f745dc5b381dc3eb78bea12b8da27409e5443d0796f47952a | the same run |
| vfpu/jit/*.port.csv (243) | | digest 14b68d78404f03860c9577ff544ce9e2bd34fe62df3bd76b0dd77682ea0e107c | `port`, the win-x64 corpus of 2026-10-08 |
| vfpu/interp/sites.json | 20836 | bbb203b9f912e2b3b32ef52551b1f53f20675f8037edad205d5067bc73f34cc3 | 2026-10-08, CPU core 0 (x64 interpreter), 27 sites |
| vfpu/interp/*.csv (27, not port) | | digest 290e9fafee12b3b3bda4de415d6a98d438761a02e2f798e455eb0a24f03e30f0 | the same run |
| vfpu/interp/*.port.csv (27) | | digest 0f5f17f786713d01abcda915e52211320d64b022cf2afc6b76e9ab66f9beb77e | `port`, the win-x64 corpus of 2026-10-08 |
