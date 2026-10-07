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

| Scene | File | Route (after `frontend.txt`) | Requested | How |
|---|---|---|---|---|
| SINGLE PLAYER (SINGLE RACE highlighted) | single_player.{png,ppdmp} | vineta_k_start.txt | 5850 | run A |
| CLASS SELECTION (VECTOR) | class_select.{png,ppdmp} | vineta_k_start.txt | 6050 | run A |
| LEAGUE SELECTION (ALPHA) | league_select.{png,ppdmp} | vineta_k_start.txt | 6250 | run A |
| TRACK SELECTION (VINETA K) | track_select.{png,ppdmp} | vineta_k_start.txt | 6450 | run A |
| TEAM SELECTION (FEISAR) | team_select.{png,ppdmp} | vineta_k_start.txt | 6690 | run A |
| Time Trial TRACK SELECTION (records, medal times) | tt_track_select.{png,ppdmp} | time_trial_start.txt | 6650 | run B |
| Time Trial, first full-HUD frame, Vineta K | tt_hud.png | time_trial_start.txt | 7302 | burst C |
| Free Play TRACK SELECTION | fp_track_select.{png,ppdmp} | free_play_start.txt | 6650 | run D |
| Free Play, first full-HUD frame, Vineta K | fp_hud.png | free_play_start.txt | 7302 | burst E |
| TOURNAMENT SELECTION (ALPHA) | tournament_select.{png,ppdmp} | tournament_start.txt | 6450 | run F |
| Zone TRACK SELECTION (PRO TOZO) | zone_track_select.{png,ppdmp} | zone_start.txt | 6250 | run G |
| Zone 1, first frame with the HUD | zone_hud.png | zone_start.txt | 6668 | burst H |
| OPTIONS, CONTROLS | options.{png,ppdmp}, controls.{png,ppdmp} | options_controls.txt | 6550, 6900 | run I |
| first full-HUD frame, Modesto Heights / Chenghou Project / Blue Ridge | modesto_heights_hud, chenghou_project_hud, blue_ridge_hud .{png,ppdmp} | vineta_k_start.txt + track_down1/2/3.txt | 7158 | run J (one per track) |
| first full-HUD frame, Sinucit, Citta Nuova, Sebenco Climb, Sol 2 | sinucit_hud.png ... sol_2_hud.png | unlock_all.txt + unlock_race_beta.txt [+ unlock_track_downN.txt] | 7662, 7664, 7670, 7652 | burst K |
| first full-HUD frame, Karbonis, Sagarmatha, Manor Top, Mandrashee | karbonis_hud.png ... mandrashee_hud.png | unlock_all.txt + unlock_race_classic.txt [+ unlock_track_downN.txt] | 7636, 7638, 7640, 7640 | burst K |
| the pause menu, Vineta K, about 450 frames after GO | pause.png | vineta_k_start.txt + vineta_k_hold_cross.txt + pause.txt | 7880 | burst L |
| the results panel after a three-lap Vineta K race | results_vineta_k.png | (`tools/fidelity_audit.py --ppsspp-race vineta_k`) | finish + 240 | the race driver |
| the system save dialog: the list, and Save completed | save_dialog.png, save_completed.png | save_yes.txt | 5200, 5400 | burst M |
| Zone 1's end panel (SHIP DESTROYED, TOTAL ZONES CLEAR 6), Cross held | zone_end.png | zone_start.txt | 11000 | run N |

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
# the results panel: out/fidelity/ppsspp/vineta_k/shots/r<finish+240>.png of
python3 tools/fidelity_audit.py --ppsspp-race vineta_k
```

The runs of 2026-10-06 (in the worktree of task 035) gave these files. Each menu scene was captured twice, by an
exploration run with a capture every 10 vblanks and by its run above, with identical pixels; the Alpha HUD frames of
run J equal those of a burst from 7100 (Modesto Heights within 0.0001 at tol 0); each burst was run once. A run
of `time_trial_start.txt` with a capture and GE dump at 6650 and one at 7302 put the race at another moment
(0.98 of the pixels differ from burst C's 7302), the load-timing effect above.

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
