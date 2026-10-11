# 071: The Windows executable's icon

Milestone: W4 follow-up (task 061's deliverable 6) | Branch: task/071-windows-exe-icon | Status: OPEN

## Goal
The Windows release executable carries the app icon, so `Wipeout Pure.exe` shows it in Explorer, on the taskbar
and in the zip a player unpacks, as the Mac app shows its .icns. Task 061 shipped the zip without it and recorded
the icon as the follow-up. With it, Explorer's Properties sheet shows a version (a VERSIONINFO resource), so the
unpacked program answers "what is this and which build" without BUILDINFO.txt.

## Read first
- docs/tasks/061-windows-packaging.md (the Result's follow-ups; what the stage and the checks are)
- packaging/make_icon.py (the icon is drawn per size from signed distance fields — extend it, do not resample
  icon.png)
- packaging/release.env (RELEASE_NAME, RELEASE_APP_ID), packaging/windows/README.txt
- tools/bundle_windows.sh (the checks; where a new check line goes)
- CMakeLists.txt (the WIN32 release block from task 061), CMakePresets.json (CMAKE_RC_COMPILER is llvm-rc already)
- docs/release.md "Windows"

## Deliverable
1. packaging/make_icon.py gains the Windows icon: `packaging/windows/pure.ico` drawn at 16, 24, 32, 48, 64, 128
   and 256 (PNG entries are fine on Windows 10), each size rendered at its own resolution as the .icns sizes are.
   Commit the .ico (the .icns is committed too); the script remains the way to regenerate both.
2. `packaging/windows/pure.rc`: the icon, and a VERSIONINFO block — FILEVERSION/PRODUCTVERSION from the project
   version (fourth field 0), ProductName and FileDescription from RELEASE_NAME, LegalCopyright naming the licence
   (GPL-2.0-or-later) — no commit hash (the .rc is a committed file; the hash lives in BUILDINFO.txt), no user
   name, no path. CMakeLists.txt compiles it into PureNative on WIN32 (both presets: the developer build may as
   well carry it; nothing compares the exe byte for byte).
3. tools/bundle_windows.sh: an eighth check, `icon` — the staged executable holds an icon resource and a version
   resource (llvm-readobj's COFF resources, or the .rsrc section plus llvm-rc's own output as evidence; say in the
   header what it reads). Update the counts where the docs say "all seven checks" (docs/release.md "Windows",
   docs/windows.md step 4's exit, docs/status.md; `grep -rn "seven checks" docs/` finds them).
4. Docs: docs/release.md "Windows" names the icon and the .rc; docs/status.md's task-061 follow-up loses the icon
   (code signing remains); `python tools/docs_check.py` passes.
5. Not in scope: the window's and taskbar's *runtime* icon is the SDL shell's (set at run time, the framework's),
   not the exe resource's. If the running window shows a default icon, record it as a follow-up; do not patch
   vendor/.

The Release build in your worktree is cold (build/release-win does not exist there): `tools/build.sh release` is
allowed and expected once, 10 to 25 minutes (ccache-warm from the main checkout; this does not count as the
blocked full rebuild). After the .rc lands, a rebuild is the resource compile and the relink, seconds.

## Acceptance criteria
- [ ] `python3 packaging/make_icon.py` writes packaging/windows/pure.ico (and the unchanged PNG/.icns paths do not
      regress: the script still runs on macOS; guard the iconutil call as it is)
- [ ] `Wipeout Pure.exe` in the stage holds the icon and the version resource; Explorer shows them (open the stage
      folder once and say what you saw, as task 061 did for the console check)
- [ ] `tools/bundle_windows.sh --check out/071-icon` passes all eight checks
- [ ] `python tools/docs_check.py` passes

## Verify
`tools/bundle_windows.sh --check out/071-icon`

## May touch
- packaging/ (make_icon.py, windows/), CMakeLists.txt, tools/bundle_windows.sh, docs/, out/

## Must not touch
- vendor/ (BLOCKED if the shell's runtime icon tempts you — record it instead), include/psprecomp/, src/,
  config/, patches/, tools/ other than bundle_windows.sh

## Estimated turns
25 — commit after each proven stage (the .ico and .rc; the build with the resource; the check; the docs), so a
turn-limit stall never loses work. On resume, finish from the artifacts that exist; do not redo the Release build.

## Escalate when
llvm-rc cannot compile the .rc (a toolchain gap); the resource breaks the link or the subsystem; the icon needs
anything from vendor/ or src/.

## Result
(worker fills) Status: | Changed: | Verify output (last 20 lines): | Open questions:

## Review
(Fable fills) Verify rerun: | Spot-read: | Merged: | Notes:
