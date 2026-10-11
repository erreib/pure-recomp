# 071: The Windows executable's icon

Milestone: W4 follow-up (task 061's deliverable 6) | Branch: task/071-windows-exe-icon | Status: MERGED (d1cf4ce, 2026-10-11)

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
Status: PARTIAL. Everything is done and Verify passes. One acceptance item is not done: the look in Explorer. This
worktree's guard refused to run powershell.exe, and the agent has no display, so I could not open the stage folder or
read the Shell's Properties fields. Erik or the reviewer needs to open it once.

Changed (commits 55b37e0, 1242b34, c2fdf8a on task/071-windows-exe-icon):
- packaging/make_icon.py: `write_ico` packs packaging/windows/pure.ico. It holds 16, 24, 32, 48, 64, 128 and 256
  pixel images, each drawn by `render(size)` at its own resolution and stored as a PNG entry (no resampling).
  The iconutil step now runs only when `shutil.which("iconutil")` finds it, so off macOS the .icns is left as it is.
  Rerunning the script on Windows rewrote packaging/icon.png with identical bytes (git sees no change). I parsed the
  .ico back: 7 entries, each a valid RGBA PNG of its size.
- packaging/windows/pure.ico (new, 13487 bytes, committed).
- packaging/windows/pure.rc (new, ASCII): `1 ICON "pure.ico"` and a VERSIONINFO:
  - FILEVERSION/PRODUCTVERSION are PURE_VERSION_MAJOR, _MINOR, _PATCH, 0. CMake passes these numbers in.
  - The FileVersion/ProductVersion strings are built from the same numbers by preprocessor stringification
    ("0.1.0.0").
  - ProductName and FileDescription are "Wipeout Pure"; LegalCopyright names GPL-2.0-or-later.
  - No hash, no user name, no path.
- CMakeLists.txt: an `if(WIN32)` block (both presets) adds pure.rc to PureNative. It sets COMPILE_DEFINITIONS from
  PROJECT_VERSION_* and makes pure.ico an OBJECT_DEPENDS. llvm-rc compiled it without trouble. The link still
  works, and the Release exe's subsystem is still IMAGE_SUBSYSTEM_WINDOWS_GUI. The developer build (`build.sh
  profile`) also rebuilds and relinks in seconds.
- tools/bundle_windows.sh: an eighth check, `icon`, described in the header. It requires:
  - `llvm-readobj --coff-resources` lists ICON (at least 7 images), GROUP_ICON and VERSIONINFO.
  - ProductName equals RELEASE_NAME and ProductVersion equals the project version plus ".0". These are read from the
    resource's UTF-16 strings by a small inline python3, because this LLVM's llvm-strings has no `-e l`.
  - `llvm-readobj --file-headers` reports the windows subsystem.
  The first run, before a pattern fix, showed the FAIL path working.
- docs/release.md "Windows": a paragraph on pure.rc and pure.ico, the exe row in the folder table, and the `icon` row
  in the check table.
- docs/windows.md step 4: exit now names the eighth check.
- docs/status.md: the task-061 follow-up now says the icon is done (eight checks PASS) and only code signing remains.
  The 2026-10-11 repack line is still "seven", because that run had seven checks; it is now marked "before task
  071's icon check".
- `python tools/docs_check.py`: 33 files, 0 findings: PASS.

Evidence instead of Explorer: llvm-readobj on the built exe shows these resources: ICON (7 entries; the 16 px entry
starts with the PNG signature, 440 bytes), GROUP_ICON, VERSIONINFO and MANIFEST. The fixed info is 0.1.0.0 / 0.1.0.0,
FILEOS 0x40004 and FILETYPE APP. The strings are CompanyName "pure-recomp", FileDescription "Wipeout Pure",
FileVersion "0.1.0.0", InternalName "PureNative", LegalCopyright "pure-recomp, GNU General Public License version 2
or later (GPL-2.0-or-later)", OriginalFilename "Wipeout Pure.exe", ProductName "Wipeout Pure" and ProductVersion
"0.1.0.0".

Verify output (`tools/bundle_windows.sh --check out/071-icon`, out/071-icon.log). The per-check lines come first,
then the last 20 lines:
```
files    PASS  16 files, as expected (.../out/071-icon/bundle_files.txt)
dlls     PASS  the program and 4 DLLs import only each other, API sets and System32's: vulkan-1.dll ws2_32.dll ...
machine  PASS  no H:/errei, H:\errei, C:/Users/erreib (either slash), erreib or dev-stuff in any file, any case
names    PASS  no file named like game data (18 entries)
content  PASS  no game file; the disc image's SHA-256 (87078aee9e4f9557...) in no file; hits only in the executable's own strings and the read-me texts:
icon     PASS  resources ICON GROUP_ICON VERSIONINFO MANIFEST: 7 icon images (packaging/windows/pure.ico), ProductName 'Wipeout Pure', ProductVersion 0.1.0.0; IMAGE_SUBSYSTEM_WINDOWS_GUI
setup    PASS  exit 0, image copied (252968960 bytes), data directory 250749 KiB: EBOOT.ELF disc.iso settings.ini; setup.log 24 lines
route    PASS  exit 4 (4: the runtime stopped, by PURE_EXIT_AT_FRAME) at frame 2200 from DIR/data, Renderer: Vulkan on NVIDIA GeForce RTX 3080, target 960x544; title: PASS fraction 0.030170 (3939/130560 pixels differ by more than 24, limit 0.05) at 480x272 (resized from 960x544 and 480x272)
---- last 20 lines ----
files of out/release-windows/stage/Wipeout Pure (bytes, path; .../out/071-icon/bundle_files.txt), 146M in all:
       549 BUILDINFO.txt
     18431 LICENSE.txt
      4323 README.txt
   2848256 SDL3.dll
  80753152 Wipeout Pure.exe
  65771520 avcodec-61.dll
   2836992 avutil-59.dll
      1104 licenses/DearImGui-LICENSE.txt
      7651 licenses/FFmpeg-LICENSE.txt
       537 licenses/FFmpeg-SOURCE.txt
      1133 licenses/PortableKit-LICENSE.txt
       884 licenses/SDL3-LICENSE.txt
     10058 licenses/THIRD_PARTY_NOTICES.md
      1235 licenses/tiny-AES-c-UNLICENSE.txt
      1415 licenses/xxHash-LICENSE.txt
    670208 swresample-5.dll
data directory after setup: 246M (EBOOT.ELF disc.iso ms0 pipeline_cache.bin pipeline_keys.bin settings.ini)

bundle_windows check: PASS
```
The stage was packed from 55b37e0 with the check edits uncommitted (version 0.1.0-55b37e0-dirty). The exe and the
icon check code are the same as in the committed tree.

Open questions:
- Explorer: someone needs to open out/release-windows/stage/Wipeout Pure once and confirm the icon and the
  Properties > Details version fields. Without that, the second acceptance criterion is only half met.
- The running window's and its taskbar button's icon: I did not look. If SDL3 does not take the exe's first icon
  for its window class and the shell sets none, the window shows a default icon. That would be a framework follow-up
  (vendor/), not done here. docs/release.md says it was not looked at.
- Cold Release build: about 1 minute in this worktree (ccache-warm), not 10 to 25.

## Review
Verify rerun: from the main checkout after the merge, 2026-10-11 — the first run FAILED the icon check, and
rightly: `--check` packed only when the stage was missing, so it judged the morning's pre-071 stage, whose exe had
no resources. The check's FAIL path is thereby proven end to end in the gate itself. Fixed at the merge:
`--check` now always re-stages (stage() rebuilds when the sources are newer), so the gate judges the current
tree. The rerun: all eight checks PASS (out/071-verify-main.log; icon: 7 images, ProductName 'Wipeout Pure',
ProductVersion 0.1.0.0, IMAGE_SUBSYSTEM_WINDOWS_GUI).
Spot-read: pure.rc carries no hash, name or path (CompanyName and LegalCopyright name the project and the
licence); the CMake block is both-presets with the version passed as numbers and the .ico an OBJECT_DEPENDS; the
icon check reads the built resources back (llvm-readobj) rather than trusting the .rc, and the VERSIONINFO
strings with a small UTF-16 reader since this llvm-strings lacks `-e l`. make_icon.py's iconutil step is guarded
by `shutil.which`, so the script runs on either system and rewrote icon.png byte-identically here.
Merged: d1cf4ce into batch/m2 (the --check fix and this review follow on top).
Notes: the PARTIAL was only the Explorer look — the worker has no display; Erik should open
out/release-windows/stage/Wipeout Pure once (the exe's icon, Properties > Details). The running window's and
taskbar button's icon (SDL window class vs the exe resource) was not looked at: if the window shows a default
icon it is a vendor follow-up, recorded in docs/release.md. Code signing remains the last 061 follow-up.
