# Setup

Machine: Apple M4 Pro, 24 GB, macOS 15.7.9, Command Line Tools only (no Xcode).

## Toolchain traps on this machine
- Two Homebrews: arm64 at `/opt/homebrew` (first on PATH) and x86_64 at `/usr/local`. Install build tools in the
  arm64 one so `cmake`, `ninja`, `pkg-config` resolve to arm64 binaries.
- `/usr/local/opt/game-porting-toolkit-compiler/bin` is first on PATH: `clang` there is x86_64 clang 8.
  Always use `/usr/bin/clang` (Apple clang 17). `CMakePresets.json` and `tools/env.sh` do this.
- No Xcode: no offline `metal` shader compiler. Metal shaders are compiled from source at runtime.
- macOS has no `timeout`; `tools/run_boot.py` enforces its own deadline.
- Python 3.13 (`/opt/homebrew/bin/python3`) has zlib but no PIL or numpy; `tools/png.py` is dependency-free.

## S1 results (2026-10-05)
Installed through the arm64 Homebrew: cmake, ninja, ccache, pkgconf, sdl3 3.4.18, molten-vk, vulkan-loader and
vulkan-headers 1.4.363, glslang, vulkan-validationlayers, ghidra 12.1.4 (with openjdk 21), and the cask
`ppsspp-emulator` (installs `/Applications/PPSSPPSDL.app`, PPSSPP 1.20.x, SDL build). Log: `out/s1-brew.log`.
ghidra-allegrex v21.4 (built for Ghidra 12.1.3) is installed into
`~/Library/ghidra/ghidra_12.1.4_PUBLIC/Extensions/ghidra-allegrex` (macOS user dir; `~/.config/ghidra` is not read) with its `version=` tag bumped to 12.1.4;
if headless import rejects it, download Ghidra 12.1.3 to `~/opt/` and set `GHIDRA_HOME`.
Reference clones under `~/dev/scratch/`: Yakumo, PortableKit, PSPRecomp, pspautotests, psp-ghidra-scripts,
psplibdoc, vfpu-docs. `tools/env.sh` puts `/opt/homebrew/bin` and openjdk 21 first on PATH.

## Ghidra headless (spike S5)
- `tools/ghidra_headless.sh import` imports `disc/PSP_GAME/SYSDIR/BOOT.BIN` with the ghidra-allegrex loader. The
  image base must be given to the loader (`-loader-imageBase 08804000`): rebasing afterwards in a script moves the
  blocks but does not re-apply the PRX relocations, so every `jal` and `lui/addiu` target stays module-relative and
  no references are created. Import plus auto-analysis takes about one minute.
- `tools/ghidra_headless.sh export` runs `tools/ghidra/ExportFunctions.java`: names import stubs from
  `config/imports.csv`, writes `config/function_map.csv`. Then `python3 tools/label_functions.py` resolves string
  references from `.rel.text` (HI16/LO16 pairs) and writes `config/function_labels.csv`, `out/strings-xrefs.csv`,
  `out/import-callers.csv`; then `tools/ghidra_headless.sh script ApplyLabels "$PWD/config"` renames the functions
  inside the project. `tools/ghidra_headless.sh script Decompile <outfile> <hexaddr>...` dumps disassembly and C.
- The project lives in `ghidra_project/` (ignored). Scripts are compiled by Ghidra on each run (about 25 s overhead).
- Ghidra's own string reference analysis finds 1,395 code-to-string references; the relocation walk finds 8,851,
  because many strings are reached through tables and `lui/addiu` pairs the analyser does not follow.

# Windows setup (task 054)

Machine: Erik's Windows 10 Pro x64, 6 threads, 64 GB, NVIDIA RTX 3080. Everything below runs from Git Bash (the
repo's bash tools run there as on macOS; `python3` resolves to a real Python 3.12 through the WindowsApps alias).

## Toolchain
- **VS 2022 Build Tools** (already present): MSVC 14.39 headers and libraries, and the `cmake` 3.28 and `ninja`
  under `Common7/IDE/CommonExtensions/Microsoft/CMake/`. No developer prompt is needed: clang-cl finds the MSVC
  installation itself.
- **LLVM 23.1.3** (`winget install LLVM.LLVM`): `clang-cl`, `lld-link`, `llvm-rc`, `llvm-mt` in
  `C:\Program Files\LLVM\bin`. The preset `win-x64` names them all; `CMAKE_MT` must be set to `llvm-mt` or CMake's
  link step fails on `CMAKE_MT-NOTFOUND`.
- **Vulkan SDK 1.4.363.0** (`winget install KhronosGroup.VulkanSDK`, into `C:\VulkanSDK`): headers, loader and
  `glslangValidator` (the preset points `PORTABLEKIT_GLSLANG` at it). The same 1.4.363 as the Mac's MoltenVK stack.
- **ccache 4.14.1** (`winget install Ccache.Ccache`): lands under
  `%LOCALAPPDATA%\Microsoft\WinGet\Packages\Ccache.Ccache_...\ccache-4.14.1-windows-x86_64` (the winget `Links`
  alias did not materialise here); `tools/env.sh` puts that directory on PATH.
- **SDL3 3.4.18** (the `SDL3-devel-3.4.18-VC.zip` from libsdl-org's releases) unpacked to
  `H:\errei\Documents\dev-stuff\deps\SDL3-3.4.18`; the preset's `SDL3_ROOT` points there and the framework copies
  `SDL3.dll` next to the executable.
- **FFmpeg**: nothing to install; on Windows the framework downloads BtbN's LGPL shared build of 7.1.5 at
  configure (cmake/FFmpeg.cmake) and stages the three DLLs into `build/win-x64/bin`.

## Traps on this machine
- No Developer Mode, no admin: `ln -s` fails, so `disc.iso` is a **hard link** to the image in `H:\errei\Downloads`
  (Downloads is redirected to H:, the repo's volume, so a hard link works); `tools/setup_game.sh` and
  `tools/purelib/port.py` fall back to hard links when `disc.iso` is not a symlink.
- `core.autocrlf=true` globally: the working tree is CRLF. Git Bash runs CRLF shell scripts, Python reads them
  fine, and `git apply` applies the patch series with "trailing whitespace" warnings that mean nothing.
- The first `clang` on PATH is irrelevant here (no Game Porting Toolkit); the preset names absolute compiler paths.
- `tools/env.sh` detects Windows by `uname -s` (MINGW*) and sets PATH for cmake, ninja, clang-cl and ccache;
  `tools/build.sh` and `tools/regen.sh` pick the `win-x64` preset the same way.

## Build and run
```
tools/build.sh configure     # preset win-x64; downloads FFmpeg on first run
tools/regen.sh               # regenerate the corpus from game/EBOOT.ELF (never copy generated/ between machines)
tools/build.sh profile       # incremental after that
tools/run_boot.py --seconds 60 out/boot.log
```
The Metal backend and shell are macOS only and are not built (CMakeLists.txt gates them on APPLE); the renderer is
the framework's Vulkan one (`PURE_GE_BACKEND=vulkan`), the window the Vulkan shell. On Windows the game's stdout
reaches the tools through a pipe, not a pty, so log lines arrive in bursts (tools/purelib/port.py).

## Windows tools (task 055)
- **PPSSPP 1.20.4** (the Mac's version), the official portable zip `https://www.ppsspp.org/files/1_20_4/ppsspp_win.zip`
  (SHA-256 a60f04ebdb0b5f1655422bd7f88349a46999b17ad5115d6ddb290c3934bd5163) unpacked to
  `H:\errei\Documents\dev-stuff\deps\ppsspp-1.20.4`; no installer, no UAC. The executable is `PPSSPPWindows64.exe`
  (`tools/ppsspp/ppsspp_ctl.py`'s `APP` on Windows); portable mode puts the memory stick, the ini and the dumps in
  `memstick/` beside it. The debugger protocol is the Mac's: a scripted run of `routes/frontend.txt` with a
  screenshot (`memory.read` of VRAM) and a GE dump at frame 600 gave a `.ppdmp` byte-identical to `ref/frontend.ppdmp`
  and a PNG 269 pixels (0.2%) off `ref/frontend.png` (the software renderer on x64).
- Process control differs: `tasklist` for the pids, `netstat -ano` for a moved port, `taskkill` (no /F: WM_CLOSE) for a
  clean quit. A CPU stopped in the debugger keeps the Windows build from closing, so the driver resumes it first.
  `--savestate` stays macOS-only (it posts the hotkey through CoreGraphics).
- `tools/worktree_init.sh` runs here: junctions (`mklink /J`) for disc/, generated/ and each directory of the main
  checkout's ref/, hard links for disc.iso and ref/'s files, the FFmpeg zip copied; a fresh worktree was ready in 52 s
  (258 ccache hits, 2 misses). Git Bash's `ln -s` copies silently without Developer Mode, so no tool may use it here.
  A junction into ref/ shares the main checkout's references: a retake in a worktree writes them there.
- The Vulkan GE backend draws only through the Vulkan shell: headless it draws nothing. Runs that read pictures (the
  frame suite's default, the sweep, the scorecard's extra scenes) open a Vulkan window on Windows
  (`purelib.port.DRAWING`) and run paced; runs that read no pictures stay headless.
- `.sh` tools started from Python go through Git Bash's `bash` by path: `bash` alone resolves to System32's (WSL's).

### The checks of docs/verification.md on Windows
| Check | Windows |
|---|---|
| `tools/imgdiff.py --selftest`, `tools/controls_check.py`, `tools/docs_check.py` | run (task 055) |
| `tools/frame_regress.sh` | runs, the Vulkan shell and backend by default (task 054: 18/18) |
| `tools/scorecard.py --quick` | runs (task 055's Verify); timing and coverage read the 46-cell matrix, not run on this machine yet |
| `tools/save_interchange.sh --check` | runs (the checker builds with LLVM's clang++) |
| `tools/ppsspp/ppsspp_ctl.py` | runs against the portable PPSSPP 1.20.4 |
| `tools/worktree_init.sh` | runs |
| headless runs (`run_boot.py --shell headless`, the scorecard's save and race-load runs) | headless without a drawing backend: saves and race loads differ from the Mac (task 055: main_menu.txt wrote no profile, the Vineta K route opened no track); under diagnosis, task TBD |
| `tools/hud_check.sh` | macOS only: it reads the Metal shell's window |
| `tools/gerec/metal_check.sh` | macOS only: it compares the Metal backend with Vulkan |
| `tools/bundle.sh --check` | macOS only: the app bundle |
| `tools/verify_task.sh 054`, `tools/refactor_check.sh`, `tools/campaign_sweep.py`, `tools/save_roundtrip.sh`, the whole `tools/save_interchange.sh`, `tools/sas_reverb_check.sh`, `tools/ai_seed_check.sh`, `tools/wavstats.py` on a `PURE_AUDIO_WAV` capture, `tools/vfpu_probe.py`, `tools/scorecard.py --refresh-references`, `tools/gerec/replay_check.sh` | not demonstrated yet (task 055 PARTIAL) |
