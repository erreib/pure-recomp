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
port and the suite rows they feed are in docs/fidelity.md ("PPSSPP references beyond the five") and
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
docs/fidelity.md, whose captures came during the load.

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
(docs/verification.md, "The SAS reverb check"). Same PPSSPP and memory stick as above; the hardware renderer, which
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
- `ref/saves/port-plain/UCUS98612P0000/`: a plain save written by the port before patch 0019 (batch/m2 at aa9128a,
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
docs/verification.md "The accuracy scorecard") and keeps it under `ref/scorecard/`, git-ignored like every capture
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
| scorecard/audio/main_menu.wav | 29128748 | 258049176cd1f991f14070c48a647ed620e86c2463c1cdfe77260b2ff5b0f280 | 2026-10-07 11:09 | PPSSPP frontend.txt + main_menu_music.txt to vblank 9900; its audio dump |
| scorecard/audio/sagarmatha.wav | 34665260 | afff66f58413169ad07d4e2a7284071bf6f27a6e06247690e1a09f825ba1d14f | 2026-10-07 11:22 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt + unlock_track_down1.txt, Cross from vblank 7696, race records to 65 s of race clock; PPSSPP's audio dump |
| scorecard/audio/sinucit.wav | 34727468 | b8340b36c9f373baedfadfa0f6f721655b4305876b9fda18ae7bfcf36f9c55c7 | 2026-10-07 10:47 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt, Cross from vblank 7720, race records to 65 s of race clock; PPSSPP's audio dump |
| scorecard/audio/vineta_k.wav | 33229356 | dd8d9af05935c1582495060b4ae4f14d6b1e3fa30f63cb0aeca8db3bf127b1d6 | 2026-10-07 10:13 | PPSSPP frontend.txt + vineta_k_start.txt, Cross from vblank 7213, race records to 65 s of race clock; PPSSPP's audio dump |
| scorecard/saves/UCUS98612P0000/ICON0.PNG | 6742 | 78cdec5c24671561c490a8096d26fb725794c42a31e3ffdcad1e6dc51d28c7e0 | 2026-10-07 11:11 | PPSSPP frontend.txt + save_yes.txt to vblank 6200 (YES on SAVE PROFILE, the first slot) |
| scorecard/saves/UCUS98612P0000/ICON1.PMF | 51200 | ae2ba722b69a0abfd8b42cea909095c045599d7b2055797f0f851f578da21fba | 2026-10-07 11:11 | PPSSPP frontend.txt + save_yes.txt to vblank 6200 (YES on SAVE PROFILE, the first slot) |
| scorecard/saves/UCUS98612P0000/PARAM.SFO | 4912 | 40c8de95d629a7d27dd7e436defef7363efaa364ba0e4d92c555b1da71a62d3e | 2026-10-07 11:11 | PPSSPP frontend.txt + save_yes.txt to vblank 6200 (YES on SAVE PROFILE, the first slot) |
| scorecard/saves/UCUS98612P0000/PIC1.PNG | 172944 | 430218db46278245ae67a971a7f505fbbad2a1a270b80bf52b46cc9c3cb7df28 | 2026-10-07 11:11 | PPSSPP frontend.txt + save_yes.txt to vblank 6200 (YES on SAVE PROFILE, the first slot) |
| scorecard/saves/UCUS98612P0000/PROFILE.BIN | 41586 | beefff0605ccf076b7e874f868e34927da436474f78d28c3dbe3b33477584aa1 | 2026-10-07 11:11 | PPSSPP frontend.txt + save_yes.txt to vblank 6200 (YES on SAVE PROFILE, the first slot) |
| scorecard/saves/UCUS98612P0000/SND0.AT3 | 97604 | c558e377092cabc09b6e388fdc3734d4965fb3eb925c1cb46dc3266df80ac5ee | 2026-10-07 11:11 | PPSSPP frontend.txt + save_yes.txt to vblank 6200 (YES on SAVE PROFILE, the first slot) |
| scorecard/timing/ppsspp/vineta_k/ppsspp.log | 1943656 | b67232ba5e8bcdf710a6451b8abbf3b2ab002e44a471205c640686926c209c25 | 2026-10-07 11:28 | tools/fidelity_audit.py --ppsspp-race vineta_k --out ref/scorecard/timing |
| scorecard/timing/ppsspp/vineta_k/summary.json | 1210 | caf52654a9d22da384d440922cddf48a20d5368ea7d4716a01da5cabdf5d985f | 2026-10-07 11:28 | tools/fidelity_audit.py --ppsspp-race vineta_k --out ref/scorecard/timing |
| scorecard/trajectories/blue_ridge.csv | 306488 | 1c543e7eb8791c7789f069a0840af70b0f87999fd4f7b9bd4ef2d93b7c962af3 | 2026-10-07 10:43 | PPSSPP frontend.txt + vineta_k_start.txt + track_down3.txt, Cross from vblank 7216, race records to 25 s of race clock |
| scorecard/trajectories/blue_ridge.flips.txt | 56237 | ff8f9d90a9ad7856a6c77dd221524eb8fd6fc9a4b4be97df4afab76aab553322 | 2026-10-07 10:43 | PPSSPP frontend.txt + vineta_k_start.txt + track_down3.txt, Cross from vblank 7216, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/chenghou_project.csv | 312141 | 979c7cd6a6dfa97ab279369a086874d0bbb8cb8db8493b0c7e827fe50a9d08c8 | 2026-10-07 10:41 | PPSSPP frontend.txt + vineta_k_start.txt + track_down2.txt, Cross from vblank 7216, race records to 25 s of race clock |
| scorecard/trajectories/chenghou_project.flips.txt | 56257 | 9b46c205cce42b046948766f8d0740165aedad21c5d50edf8a5ff53f1cd1ca2d | 2026-10-07 10:41 | PPSSPP frontend.txt + vineta_k_start.txt + track_down2.txt, Cross from vblank 7216, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/citta_nuova.csv | 304747 | 0e5d2a9a39752b9f412278fd1ece719c943c3126b2278da30ac331bc47208ba0 | 2026-10-07 10:49 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt + unlock_track_down1.txt, Cross from vblank 7722, race records to 25 s of race clock |
| scorecard/trajectories/citta_nuova.flips.txt | 61006 | 13a756fdd72f4651f0d647b2edeb7a1a91173d6f589cffff04e4f0883f2c4fe7 | 2026-10-07 10:49 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt + unlock_track_down1.txt, Cross from vblank 7722, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/karbonis.csv | 318198 | 2d35b4810fb392f4bdc7cbf9f1aa436e04b6951d24cc7b7dd4ef92baa4816e02 | 2026-10-07 10:58 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt, Cross from vblank 7694, race records to 25 s of race clock |
| scorecard/trajectories/karbonis.flips.txt | 60759 | 504d8d0ab0736a399967efc02ddeb602d070837a70b1c64a35f2cabb6d2e7c23 | 2026-10-07 10:58 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt, Cross from vblank 7694, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/mandrashee.csv | 322394 | 8793afa5a20efb252ff6e3b59634dd100553a946e862a7a56575f4a18b09383a | 2026-10-07 11:06 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt + unlock_track_down3.txt, Cross from vblank 7698, race records to 25 s of race clock |
| scorecard/trajectories/mandrashee.flips.txt | 60737 | ae27a64a2e40fd8008eefa3c5312d668a7ba07038ead40189a6d48621a478095 | 2026-10-07 11:06 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt + unlock_track_down3.txt, Cross from vblank 7698, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/manor_top.csv | 303651 | 0a95cb59c0c3d0412339555cd71c0c482bf4264fcd67594d4835abf0d78a54a2 | 2026-10-07 11:04 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt + unlock_track_down2.txt, Cross from vblank 7698, race records to 25 s of race clock |
| scorecard/trajectories/manor_top.flips.txt | 60857 | f7e47133d400b51504a3586d38bafd55e8c8c5dc43bba103b35d9f230bb6cf9f | 2026-10-07 11:04 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt + unlock_track_down2.txt, Cross from vblank 7698, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/modesto_heights.csv | 310340 | 677a50dcb5f4ce9cdd2be9155c236ff16ce1efe8ab0c42fb27d1fa62838bc055 | 2026-10-07 10:38 | PPSSPP frontend.txt + vineta_k_start.txt + track_down1.txt, Cross from vblank 7216, race records to 25 s of race clock |
| scorecard/trajectories/modesto_heights.flips.txt | 56238 | 0a27707805a14cbff99989004ae4ef90e22f081035d64eb967dbee1b998a70e7 | 2026-10-07 10:38 | PPSSPP frontend.txt + vineta_k_start.txt + track_down1.txt, Cross from vblank 7216, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/sagarmatha.csv | 800227 | 27ece46ff3a634572d212be5ba656ae7f39aca2e2108c448aecaa3b2a42b82be | 2026-10-07 11:22 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt + unlock_track_down1.txt, Cross from vblank 7696, race records to 65 s of race clock |
| scorecard/trajectories/sagarmatha.flips.txt | 108758 | ecd1de11d72632a3478d76811876f3a6feba5062ca78c0c1f8f6acf71e9dc7cc | 2026-10-07 11:22 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_classic.txt + unlock_track_down1.txt, Cross from vblank 7696, race records to 65 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/sebenco_climb.csv | 311841 | e4fdb5faf052f5804da65602a1c4974b435a2553e28ec13dccb8354a11c7f6f4 | 2026-10-07 10:52 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt + unlock_track_down2.txt, Cross from vblank 7728, race records to 25 s of race clock |
| scorecard/trajectories/sebenco_climb.flips.txt | 60983 | f265f5a9cc67ae555cb2523eeefa951231f0d26a4ccbd65ced4f16a35fe978c4 | 2026-10-07 10:52 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt + unlock_track_down2.txt, Cross from vblank 7728, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/sinucit.csv | 807597 | be0a0f491e10360ce3c305362ca1de132f52e8f9a7881e76214436cfc5fdf479 | 2026-10-07 10:47 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt, Cross from vblank 7720, race records to 65 s of race clock |
| scorecard/trajectories/sinucit.flips.txt | 108926 | e68323e8658bfdfccd7f165091d6efe3e09833e55830cdc66b087032f970749a | 2026-10-07 10:47 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt, Cross from vblank 7720, race records to 65 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/sol_2.csv | 302066 | 7054c81b613f5357e1ba23ac20b8b18e5265436b8a1648cc0276d8ae6fdd41ae | 2026-10-07 10:55 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt + unlock_track_down3.txt, Cross from vblank 7710, race records to 25 s of race clock |
| scorecard/trajectories/sol_2.flips.txt | 60603 | 19330eb6a6aa6779cbc718ec22279abdc7ab3cc78c2287867469b3d8009b8c67 | 2026-10-07 10:55 | PPSSPP frontend.txt + unlock_all.txt + unlock_race_beta.txt + unlock_track_down3.txt, Cross from vblank 7710, race records to 25 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/vineta_k.csv | 829724 | ae220eaad3875b56112840c556aa9edca8dc3fb8e1ffc240ba46190bd1a10419 | 2026-10-07 10:13 | PPSSPP frontend.txt + vineta_k_start.txt, Cross from vblank 7213, race records to 65 s of race clock |
| scorecard/trajectories/vineta_k.flips.txt | 104080 | 41e29d930583f4c20f8e5951e7afd5e4c89f9ef9f23234148e7f492a215ee8eb | 2026-10-07 10:13 | PPSSPP frontend.txt + vineta_k_start.txt, Cross from vblank 7213, race records to 65 s of race clock; every flip (usec, the player's clock) |
| scorecard/trajectories/vineta_k.run2.csv | 317891 | e0c58472cd30cffe48a633d2568f1d21402a283b750fb1f6eea043c5814cb7e0 | 2026-10-07 10:15 | PPSSPP, Vineta K again: the AI ships' determinism check |
| scorecard/trajectories/vineta_k.run2.flips.txt | 56200 | 43c98e6ee42fb574d04e96646717369d90a54500d04c6a6184e4677f2b9d45d4 | 2026-10-07 10:15 | the second run's flips |
<!-- scorecard references: end -->
