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

## Installs (spike S1)
See the install log in `docs/setup.md` once S1 completes.

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
