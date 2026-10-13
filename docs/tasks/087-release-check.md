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

**Status: BLOCKED.** All five deliverables are done and committed (5843038, e91d443, 9ed7b67). The Verify line fails
on one rule only, `home`: six real findings in files outside "May touch", so the review has to decide them (Open
question 1). Everything else in the line passes when run on its own:
- `--history`: PASS. No key, token or game file was ever committed, so the escalation condition did not occur.
- `--archive` on the fresh zip: PASS.
- `docs_check`: PASS.

Findings (HEAD 9ed7b67), each the rig's user folder:
- CMakePresets.json:38 (the `win-x64` preset's `SDL3_ROOT`)
- docs/setup.md:56, :62 and :88
- tools/env.sh:15 (the Windows `CCACHE_DIR` default)
- tools/ppsspp/ppsspp_ctl.py:39 (PPSSPP's path)

**Changed:**
- tools/release_check.sh (new). Python's standard library inside a bash wrapper. The rules are listed in its header
  and in docs/release.md's "Publishing" table.
  - The tree: HEAD's files, which is what a push publishes.
  - `--history`: the paths and names rules on every path ever added (`git log --all --no-renames --diff-filter=A
    --name-only -m`, without the stash), and the keys, tokens, binary and game-header rules on every reachable file
    version (`git rev-list --objects --all`, 1658 versions, 46.2 MB, 3.6 s). This replaces `git log -p` and also
    sees content that only a merge added.
  - `--archive`: the zip entries' names and headers, BUILDINFO.txt (in the zip or beside it: its version is the
    zip's, its commit is in this repository and was built clean, and a release version needs its tag on that
    commit), and the macOS app's Resources.
  - The allow list for hex runs, which it prints:
    - a 64-digit run with SHA-256 named on its line, on the two lines before it, or in its Markdown table's header;
    - a 40-digit run named a commit, tree or PIN there, or a commit of this repository;
    - a hash column of config/*.csv;
    - vendor/PIN;
    - a run of one repeated digit (padding).
  - A suspected key or token is printed by its first 8 digits only.
- tools/bundle.sh and tools/bundle_windows.sh have the same `release_version` (checked with `cmp`).
  - The name is the project version alone when `git tag --points-at HEAD` holds `v<version>` and no tracked file
    has uncommitted changes. Otherwise it is `<version>-<hash>[-dirty]`. `git describe --exclude='*'` keeps a tag
    out of the hash, which plain `git describe` would let in once v-tags exist.
  - A disagreeing v-tag stops the pack before the build.
  - BUILDINFO.txt keeps the full commit either way. The packer writes `git rev-parse HEAD`, and so does
    bundle_windows.sh, so nothing was added.
  - bundle_windows.sh's machine row reads README.txt and the notices without `SOURCE_URL` (see Open question 3).
- packaging/macos/README.txt and packaging/windows/README.txt: `https://github.com/erreib/pure-recomp`, with the
  tag or commit to take.
- packaging/THIRD_PARTY_NOTICES.md: names the repository and the tag or commit, and points at the read-me for the
  address (see Open question 2).
- docs/release.md:
  - "Publishing": the steps, the version from the tag, the check's table and its first figures, and what the GPL
    asks.
  - The two version lines and the Windows machine row.
- docs/verification.md: a row for the check.
- docs/status.md:
  - The Vendor row now says "the patches in `patches/`" with 28 as the count.
  - The stale "becomes 0010" follow-up is corrected.
  - The source-URL follow-up is updated.
  - New R1 bullet; the open call is updated.
- docs/windows.md: "our nine patches" now reads "the patches in `patches/`", and step 5 says how a release is named.

**Runs:**
- `tools/bundle.sh --zip` gave `pure-recomp-0.1.0-e91d443-macos-arm64.zip` in 8 s, with the release build already
  current from ccache.
- `tools/bundle.sh --check out/087-bundle`: all eight PASS (route title 0.000237).
- `--archive` on that zip: PASS (87 entries, 14 Resources text files read).
- Tag dry run on `scratch/087-tag-dry-run` at e91d443:
  - `v0.2.0`: `release version: FAIL: HEAD is tagged v0.2.0 but CMakeLists.txt's version is 0.1.0`, exit 1,
    before the build.
  - `v0.1.0`: the pack gave `pure-recomp-0.1.0-macos-arm64.zip`, Info.plist 0.1.0, and BUILDINFO.txt reads
    "Wipeout Pure 0.1.0 ..." and "Built from: e91d443ad4055eec2c4441bdab3f0d43c55474bd". `--archive` passed
    while the tag existed and failed once it was deleted.
  - With a tracked file edited at the tag: `0.1.0-e91d443-dirty`, plus a warning.
  - Both tags and the scratch branch are deleted. `git tag --list` is empty, and nothing was pushed.
- Self-test on a throwaway repository in the scratchpad: every planted case was found, and the GE-command set
  (17 bytes), padding and hashes were left alone.
- The packer's `--version` takes the name, so no vendor change was needed.
- No file under src/, config/, vendor/ or patches/ changed, so the headless suite is untouched.

**Verify output (last 20 lines):**
```
note: docs/tasks/075-texture-detail.md:219: 1 home path(s), a task's record, e.g. /Users/erreib
note: docs/tasks/082-guest-frame-profile.md:141: 1 home path(s), a task's record, e.g. H:/errei
note: docs/tasks/083-corpus-inlining.md:153,157,159,161,...: 6 home path(s), a task's record, e.g. H:/errei
note: docs/tasks/084-ultrawide-view.md:35: 1 home path(s), a task's record, e.g. /Users/erreib
note: docs/tasks/085-vulkan-orthographic-fit.md:195,197,199,201: 4 home path(s), a task's record, e.g. /Users/erreib
note: docs/tasks/086-metal-fill.md:189,190: 2 home path(s), a task's record, e.g. /Users/erreib
note: tools/bundle_windows.sh:32,342,358: 5 home path(s), a machine check's own pattern, e.g. H:/errei
note: tools/release_check.sh:31,32,85: 9 home path(s), a machine check's own pattern, e.g. /Users/NAME

check     result  detail
paths     PASS    no file under disc/ game/ generated/ vendor/ build/ out/ ref/ (but ref/README.md) or the other ignored paths; 344 files
names     PASS    no game-data extension, game file name or game file header
size      PASS    no file over 1 MiB; largest config/function_map.csv, 318026 bytes; limit 1048576
binaries  PASS    no binary file but the known three; 3 binary files
keys      PASS    no key-sized hex run or 16-byte array; the allow list took 159 SHA-256 (64 digits, named so), 6 git object id (40 digits, a commit, tree or pin)
tokens    PASS    no GitHub, GitLab or AWS token, no PEM block
home      FAIL    6 finding(s) above; 76 as notes in 30 files
history   PASS    no game path, name or header, no binary but the known three, no key or token; 824 commits, 393 paths ever added, 1658 file versions (46.2 MB) read in 3.6 s; the allow list took 1443 SHA-256 (64 digits, named so), 15 git object id (40 digits, a commit, tree or pin)
release_check: FAIL (1 of 8 checks) in 4.5 s
verify 087: FAIL (exit 1)
```
The rest of the line, run on its own:
- `tools/release_check.sh --archive out/release-macos/dist/pure-recomp-*.zip`: `archive PASS ...
  pure-recomp-0.1.0-e91d443-macos-arm64.zip: 87 entries, BUILDINFO.txt (beside it): 0.1.0-e91d443, commit
  e91d443ad405, 14 text files of Contents/Resources read`. The only FAIL row is the same `home` row.
- `python3 tools/docs_check.py`: `docs_check: 34 files, 0 findings: PASS`.

**Open questions:**
1. **The six home findings** (they block the Verify).
   - To fix them: SDL3_ROOT and PPSSPP's path from the environment (`$env{}` in the preset), a CCACHE_DIR default
     relative to the checkout, and `<deps>` in setup.md.
   - Or, if the rig's folder may be public, add those files to the note lists, `NOTE_FILES` or `CHECKER_FILES` in
     tools/release_check.sh.
2. **The source URL cannot go in the notices without a vendor change.** The GitHub account is this Mac's user name,
   so the address contains `/erreib/`.
   - The framework packer's machine-path check (`grep -e "/$(id -un)/"` over the app, in `release_macos.sh`) would
     refuse the app, and so would `tools/bundle.sh --check`'s machine row.
   - A `@SOURCE_URL@` marker is not possible either: the packer substitutes only `@MINIMUM_SYSTEM_VERSION@`, only in
     README.txt, with one fixed `sed -e`, and copies the notices as they are. bundle_windows.sh copies both as they
     are.
   - So the URL is in the two read-mes, and the notices point at the read-me. The macOS read-me ships beside the
     app, where neither check looks.
   - The alternative is a vendor patch that narrows the packer's check to `$HOME` and the checkout and build paths.
3. **bundle_windows.sh's machine row was not run on the rig.** The row reads README.txt and the notices without the
   source address, because on the rig the user name is also the account. I ran the changed block, extracted, on the
   Mac against five scratch folders, and all gave the expected result. Run `tools/bundle_windows.sh --check DIR` on
   the rig.
4. **Outside what the check can judge, for Erik before publishing archives.**
   - The app's executable carries the recompiled game code (docs/release.md's table: "the recompiled code"; the
     release PureNative is 68 MB), but both read-mes say "it contains no part of the game: no code".
   - The GPL's "complete corresponding source" of that binary would include the generated corpus, which never
     enters git (D-006).
5. **Stale counts outside "May touch".**
   - patches/README.md:10 still says "into the nine below"; there are 28 patches.
   - docs/status.md's M9 row and the organisation follow-up keep "nine patches by topic" as task 052's dated
     history.
   - batch/m2's new README.md, CHANGELOG.md and CLAUDE.md (1687681) have no home path, key-sized run or "nine
     patches".
6. **The private GitLab address will be public.** docs/status.md's Branches bullet names the address of Erik's
   private GitLab remote, and it goes public with the repository.

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
