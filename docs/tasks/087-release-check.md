# 087: The release check and the tagged version (the first public release)

Milestone: R1 (public release) | Branch: task/087-release-check | Status: OPEN

## Goal
Before the repository and its archives go public on GitHub, one command proves what the hard rules promise: the
repository holds no byte of the game, no DLC key and no personal secret, and a release archive holds no game file.
And a release gets a proper version: a git tag `v0.1.0` on the release commit names the archives `0.1.0` instead of
`0.1.0-<hash>`, with the commit still recorded in BUILDINFO.txt. The planning session writes the public README and
the release notes in parallel; this task does not touch README.md, CLAUDE.md or CHANGELOG.md.

## Read first
- CLAUDE.md "Hard rules"; .gitignore; packaging/release.env (`RELEASE_GAME_NAMES`, what the packer refuses);
  docs/release.md ("Build and bundle", "What the app holds", "The check", "Windows"); tools/bundle.sh and
  tools/bundle_windows.sh (the version line: CMakeLists.txt's project version and `git describe --always --dirty`);
  vendor/portablekit/scripts/release_macos.sh (`--version`, its own artifact scan)
- docs/dlc.md (what a DLC key is and why none may be committed: a 16-byte XTEA key per pack, the RSA modulus);
  config/ (what it may hold: addresses, names, NIDs, hashes; `function_labels.csv` holds source-path strings the
  game's binary carries, which are file names, not code)
- tools/docs_check.py (the shape of a repository-wide check in this port: findings with file:line, PASS/FAIL);
  docs/verification.md's tools table; tools/purelib/port.py

## Deliverable
1. `tools/release_check.sh [--archive ZIP ...] [--history]`: PASS or FAIL with findings as file:line (or path), exit
   0 only on PASS.
   - Tracked files (`git ls-files` at HEAD): none under the ignored game and build paths (disc, game, generated,
     vendor, build, out, ref except ref/README.md, ghidra_project); no file with a game-data extension (.iso, .bin,
     .wad, .at3, .pmf, .prx, .elf, .ppst, .ppdmp, .gerec, .sfo, .cso) or named after the game's files
     (`RELEASE_GAME_NAMES`'s globs, PI.WAD, PARAM.SFO, ICON0.PNG, DATA.BIN); no file over 1 MB (the function map is
     318 KB, the largest patch 215 KB; name the limit); only text or the known binaries (packaging/icon.png,
     packaging/macos/Wipeout Pure.icns, packaging/windows/pure.ico).
   - Content: no 32-hex-digit or 16-byte-array literal that could be a key, outside an allow list of hash columns
     (config/*.csv's hash fields, docs that cite SHA-256 sums, `vendor/PIN`); say what the allow list is. No
     private token patterns (`ghp_`, `glpat-`, `AKIA`, `-----BEGIN`). No absolute home paths outside docs/tasks/,
     docs/history/ and docs/research.md, where a machine's path in a task's record is history, not a leak (print
     them as notes, not findings).
   - `--history`: the same file-name and key scans over every commit (`git log --all --diff-filter=A --name-only`
     for names; `git log --all -p` grepped for the key and token patterns), so a leak in a past commit is found
     before the history goes public. Slow is fine (the pack is under 1 MB); say how long.
   - `--archive ZIP`: the zip's listing holds no game file (the same name and extension rules) and its BUILDINFO.txt
     names a commit that is in the repository; for the macOS zip also that the app's Resources hold no game data
     path. Run it on out/release-macos/dist/*.zip when one exists (build one with `tools/bundle.sh --zip` if not;
     the release build takes a few minutes).
   - Prints a summary table and `release_check: PASS` or `FAIL`. About 10 s without `--history`.
2. The version from a tag: `tools/bundle.sh` and `tools/bundle_windows.sh` name the artifacts `<project
   version>` alone when HEAD is exactly at a tag `v<project version>` and the tree is clean (`git describe --tags
   --exact-match` succeeds and matches CMakeLists.txt's version), else `<version>-<hash>[-dirty]` as today; a tag
   that disagrees with CMakeLists.txt's version is a FAIL, printed. BUILDINFO.txt keeps the commit hash either way
   (check what the packer writes and add the hash if it would be lost). `tools/bundle.sh --check` and
   docs/release.md's "The check" keep passing.
3. docs/release.md gains a "Publishing" section: the steps to cut a release (bump CMakeLists.txt's version, update
   CHANGELOG.md (the planning session writes it), tag `v<version>` on main, `tools/release_check.sh --history
   --archive ...`, `tools/bundle.sh --zip` here and `tools/bundle_windows.sh --zip` on the rig at the same tag, the
   SHA256SUMS, a GitHub release with both zips as assets and the notes as its body, which Erik does by hand since
   the session never pushes), and what the GPL asks of a distributed build (the source URL in the notices and the
   app's read-me: check packaging/THIRD_PARTY_NOTICES.md and packaging/*/README.txt name where the source lives,
   and change "the repository" wording to a placeholder the release fills, `@SOURCE_URL@`, only if the packer
   substitutes such markers (it substitutes `@MINIMUM_SYSTEM_VERSION@`; find how, and say in the Result whether a
   source URL marker is possible without a vendor change; if not, write the URL into the two read-mes and the
   notices as plain text, `https://github.com/erreib/pure-recomp`).
4. Stale counts: docs/status.md's Vendor row and any other doc saying "nine patches" (README.md excepted: the
   planning session rewrites it) say the current count or "the patches in patches/".
5. docs/verification.md: a row for the check; docs/status.md: an R1 bullet (what the check covers, its figures).

## Acceptance criteria
- [ ] `tools/release_check.sh --history` PASS on batch/m2 (or its findings are real and listed in the Result for the
      review to act on; the history is 800 commits, so a finding there is a decision, not a fix in this task).
- [ ] `tools/release_check.sh --archive out/release-macos/dist/pure-recomp-*.zip` PASS on a fresh `tools/bundle.sh
      --zip`, and `tools/bundle.sh --check out/087-bundle` PASS.
- [ ] A dry run of the tag naming: on a scratch branch, tag `v0.1.0` at HEAD, `tools/bundle.sh --zip` names the zip
      `pure-recomp-0.1.0-macos-arm64.zip` and BUILDINFO.txt carries the commit; delete the scratch tag after (never
      push a tag, never tag main: the release tag is Erik's step).
- [ ] `python3 tools/docs_check.py` PASS; the headless suite untouched (no game code changed).

## Verify
`tools/release_check.sh --history && tools/release_check.sh --archive out/release-macos/dist/pure-recomp-*.zip && python3 tools/docs_check.py`

## May touch
- tools/release_check.sh (new), tools/bundle.sh, tools/bundle_windows.sh, tools/purelib/port.py (a helper only if
  needed)
- docs/release.md, docs/verification.md, docs/status.md (the Vendor row's count, an R1 bullet), docs/windows.md (the
  rig's bundle line if its naming changes), packaging/THIRD_PARTY_NOTICES.md and packaging/macos/README.txt,
  packaging/windows/README.txt (the source URL only), docs/tasks/087-release-check.md

## Must not touch
- README.md, CLAUDE.md, CHANGELOG.md (the planning session's); CMakeLists.txt's version (Erik's release step);
  vendor/ (no patch unless the version naming forces one: then stop and say so); src/; config/; .claude/
- git tags on main or any push

## Estimated turns
40

## Escalate when
- The history scan finds a real key, token or game file in a past commit (list it; the review decides between a
  history rewrite and a fresh history).
- The packer cannot be given the version without a vendor change.
- Anything would touch vendor/ or push.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
