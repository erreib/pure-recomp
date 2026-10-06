# 032: A test-only unlock-all switch, racing lines from the port's own AI, every track in the sweep

Milestone: M5 (breadth) | Branch: task/032-unlock-all-and-breadth | Status: OPEN

## Goal
The sweep covers the Alpha league's four tracks because a fresh profile unlocks nothing else. The game has a
developer switch for that: bit 0 of the PSP's GPI register, read through `sceKernelGetGPI`, which every frontend lock
check treats as "everything unlocked" (`unlocked = (GPI & 1) ? 1 : profile->0x381`, where the profile byte is what
the main menu's hidden button sequence sets). Our HLE returns 0 for GPI. This task adds `PURE_TEST_UNLOCK_ALL=1`, which
makes it return 1, and uses it to put every track, class and league into the sweep: routes for the longer menus,
racing lines for the new tracks recorded from the port's own AI ships (not PPSSPP), MODES rows and budgets, and one
Single Race cell per new track run to its results screen with the no-damage switch.

## Read first
- CLAUDE.md, docs/status.md (Follow-ups: the unlock rows; M5), docs/tracks.md, docs/tasks/016, 017 and 018 (the
  follower, the no-damage switch, the modes), docs/timing.md (GPI bits 0x20/0x40/0x80 are the frame limiter's; bit 0
  is not), docs/verification.md
- src/profile/pure_profile.cpp (`register_pure_hle`: the `sceKernelGetGPI` override returning 0; the
  `PURE_TEST_NO_DAMAGE` switch and `watch_ship`, the race record array at 0x08B72010 + k * 0x1C0 with the player at
  k = 7, fields pos +0, lap +0x10, dist +0x18)
- tools/campaign_sweep.py (MODES, `Leg`, `AiLine`, the follower; how a cell's route reaches a track by DOWN presses
  on the TRACK screen), tools/pp_lines.py (how a racing line is extracted from PPSSPP's AI ships and the `.line.csv`
  format the follower reads), config/pad_scripts/single_race.txt, config/pad_scripts/drive/*.txt and *.line.csv
- out/unlock/ in the main checkout (read only): `unlock_fns.txt` (FUN_0894d4c8: the main menu's sequence
  2,3,2,8,9,8,3,2,3,9,8,9 of the game's button codes sets profile+0x381 and shows "Everything"), `gpi_fe.txt` (three
  frontend screens reading `GPI & 1`), the unlock-type name table at 0x08AB4A0C (Billboard, League, Music, Skin, Team,
  Tournament, Track, Liveries, Flash/Rapier/Phantom Class)

## Deliverable
1. `PURE_TEST_UNLOCK_ALL=1`: `sceKernelGetGPI` returns 1 (bit 0 only) in our profile's override; documented as a
   test-only switch beside `PURE_TEST_NO_DAMAGE` in README.md. Check what it opens: with the switch, from a fresh
   profile, capture the CLASS, LEAGUE and TRACK screens of Single Race and the Zone track screen (`<cell>-menu`-style
   shots in out/032/) and list every entry each shows; without the switch, the same screens as today. Also note
   whether the switch changes anything else visible in a 2200-flip frontend run (it must not: GPI bit 0 is read only
   by the lock checks and copied to GPO at boot).
2. Racing lines from the port: `PURE_WATCH_GRID=1` in the profile prints, every flip of a race, one line per
   entry of the race record array (k = 0..7): `[pure] grid frame N k=K pos=x,y,z dist=D lap=L` (the same fields the
   ship probe prints), and `tools/pp_lines.py --port LOG` turns such a log into the same `.line.csv` the follower
   reads (the AI ship with the most progress over the race, as pp_lines.py chooses from PPSSPP's). Check it on Vineta
   K: a line from a port run against the existing PPSSPP line (`config/pad_scripts/drive/vineta_k.line.csv`): report
   the mean and maximum distance between the two lines over the lap; the follower must still PASS Vineta K with the
   port line (`--line`).
3. Routes and MODES: with the switch, routes through the longer CLASS, LEAGUE and TRACK lists (the DOWN counts per
   entry; `single_race.txt` takes the class, league and track as steps the sweep writes, as task 018 did for the
   modes), MODES rows for every track of every league in Single Race, the Zone tracks 2 to 4, and the classes
   (`--class NAME`, default Vector), with frame budgets from the lap lengths. Record each new track's line (item 2)
   from a port run with the switch, Cross held, no steering (the AI ships race by themselves), as
   `config/pad_scripts/drive/<track>.line.csv` plus a `<track>.txt` with the follow line, as the Alpha tracks have.
4. Run one Single Race cell per new track (every track outside Alpha; Vector class) with `--no-damage` to the results
   screen, and the Zone tracks 2 to 4 to the SHIP DESTROYED panel; record lap times, contacts and any halt in
   docs/tracks.md (a table per league). A cell that stalls is recorded with its stall shot; do not tune the follower
   per track beyond the `--set` parameters the Alpha tracks use.
5. docs/tracks.md: the leagues and their tracks, the class list, the switch, how lines are recorded from the port, the
   cells' table. README.md: the switch, `PURE_WATCH_GRID`, `pp_lines.py --port`.

## Acceptance criteria
- [ ] With `PURE_TEST_UNLOCK_ALL=1` the TRACK screen lists tracks beyond Alpha's four and the CLASS screen more than
      Vector (the shots and the list in Result); without it, today's screens.
- [ ] `tools/pp_lines.py --port` makes a Vineta K line within 5 m mean of the PPSSPP line, and the follower PASSes
      Vineta K with it.
- [ ] Every track outside Alpha has a line and a MODES row, and its Single Race cell reaches the results screen with
      `--no-damage` (or its stall is recorded with the reason).
- [ ] Zone tracks 2 to 4 reach the SHIP DESTROYED panel and their zone counts are recorded.
- [ ] Without the switch, `tools/frame_regress.sh` is unchanged (5/5 at the Metal column) and
      `tools/campaign_sweep.py single_race vineta_k --no-damage` still PASSes.

## Verify
`tools/build.sh profile && python3 tools/campaign_sweep.py single_race sinucit --no-damage && python3 tools/campaign_sweep.py zone zone_2 && grep -c PASS out/sweep/summary.txt`

(Use the first Beta track's name as the sweep names it; change `sinucit` in this line to that name when you add the
row, and say so in Result.)

## May touch
- src/profile/pure_profile.cpp (the GPI override and the grid probe only), tools/campaign_sweep.py, tools/pp_lines.py,
  config/pad_scripts/ (routes, drive tables, lines), docs/tracks.md, README.md

## Must not touch
- vendor/, patches/, src/gpu/, src/host/, src/hle/, src/tools/, tools/run_boot.py, tools/frame_regress.sh, ref/,
  CMakeLists.txt

## Estimated turns
80 (the cells take about 7 minutes each, windowed; run them in the background and in sequence)

## Escalate when
The switch opens nothing (report the GPI call sites you checked with `PURE_TRACE_CALLS` and stop), a track halts the
game (a stub, an unsupported instruction, a runtime stop: record it and move on; stop only if the menu route breaks),
or a track's AI ships do not race with Cross held and no steering (report; that track gets no line).

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
