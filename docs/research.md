# Research notes (2026-10-05)

Founding research for the Wipeout Pure recomp, lifted from the approved plan. Facts here are point-in-time; verify before relying on file paths or API names.

## Claude Code routing mechanics (confirmed against docs 2026-10-05)

- Project `.claude/agents/<name>.md` frontmatter: `name`, `description`, `model` (`opus`, `sonnet`, `haiku`, `fable`, or full id), `tools`, `disallowedTools`, `permissionMode`, `maxTurns`, `isolation: worktree`, `memory: project|user|local`, `skills`, `hooks`, `mcpServers`. Project agents take precedence over `~/.claude/agents/`.
- Model resolution: per-call `model` on the Agent tool > agent file `model` > `CLAUDE_CODE_SUBAGENT_MODEL` env > parent model.
- Non-fork subagents start fresh: no parent history, but project `CLAUDE.md` is loaded. So the brief plus repo docs must be self-contained.
- `isolation: worktree`: own git worktree; commits on its branch survive; worktree auto-removed only if unchanged.
- Nesting allowed (3 deep by default). Background subagents run concurrently; `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` caps them.
- Project `.claude/settings.json` can pin `model` for the main session (not needed: Erik runs Fable sessions by choice).

## Facts from the disk survey (2026-10-05)

- Nothing PSP or Wipeout on the machine: no dump, no PPSSPP, no Ghidra, no Java/JDK, no PSP SDK.
- rabbitizer (vendored by PS2Recomp's build at `~/dev/bouncer-recomp/build/tools/_deps/rabbitizer-src`) already decodes R4000 Allegrex incl. VFPU.
- Toolchain traps carry over: `/usr/bin/clang` explicitly (PATH clang is GPTK x86_64 clang 8), cmake/ninja are x86_64 so pass `-DCMAKE_OSX_ARCHITECTURES=arm64`; ffmpeg x86_64 only; no PIL/numpy in any python; Rust 1.98 arm64; Node 24; brew has sdl2.
- 146 GiB free (was 11 GB during Bouncer).
- Machine: Apple M4 Pro, 24 GB RAM, macOS 15.7.9, Command Line Tools only (no Xcode, so no offline `metal` shader compiler; shaders compile at runtime from source as in Bouncer).
- Bouncer ISO symlink is dangling (`disc.iso` → `~/Downloads/Bouncer, The (USA) (En,Ja).iso` missing). Not our problem here, but the Bouncer runner won't run until restored.
- Reusable from Bouncer: vendor + numbered patches workflow (`tools/patches.sh`), `run_boot.py` harness shape, record/replay harness idea (`gsbench`, `vu1bench`), Metal backend structure (registry by name, `.mm` via `-x objective-c++`, shaders as header string, lazy GPU buffers + CPU fallback, bit-exact float rules), write-watch/call-trace levers, function-map heuristics.
- Not reusable: all 30 PS2Recomp patches, GS memory specifics, VU translation internals.
- PS2Recomp's recompiler proper is ~14k lines (`r5900_decoder.cpp` 1.1k, `ps2_recompiler.cpp` 2.4k, `elf_parser.cpp` 2.6k, control-flow analyzer/emitter ~1k, rest VU/MMI helpers). Its generated Bouncer code is 1.2M lines. A fresh Allegrex-to-C translator of the same shape is a bounded job, and rabbitizer already has the Allegrex + VFPU decode tables (4.3k lines of generated tables, test suites under `tests/asm/r4000allegrex/`).
- No per-agent model routing exists anywhere yet (`~/.claude/agents/` has only tldraw-offline, model sonnet). Global settings pin `model: fable`.

## Research: PSP recomp landscape (web, 2026-10-05)

A wave of PSP static recomps appeared June to October 2026. Verified repos (GitHub `created_at`/`pushed_at`):

| Project | License | What it is | macOS arm64 |
|---|---|---|---|
| [PSPRecomp](https://github.com/jessicanataliagta/PSPRecomp) | MIT, C++20 | Allegrex→C++ AOT translator + interpreter fallback. Core is thin: decoder, elf32/PRX loader+relocs, guest_memory, nid_registry, program_analysis, runtime. Kernel/GE/audio/input live in a per-game **profile**. Hooks for overlay swapping and `register_native_fast_path()`. No decryption shipped. Reference profile: GTA VCS on DX12 | via ports |
| [Yakumo](https://github.com/TeamGDB/Yakumo) (MHP3rd) | MIT, on PSPRecomp | "100% complete": full EBOOT + 355 overlays AOT, kernel on a deterministic virtual clock (threads, sema, evflags, mutex, vtimer, vblank), **Vulkan GE** (CLUT, DXT, swizzle, skinning, lighting, fog, per-FB render targets; no Bezier/spline), sceSas + FFmpeg 7.1 (ATRAC3/3+/H.264), PSP-format savedata, adhoc via relay. 244/296 imports. Clean-room claim (`docs/SOURCE_PROVENANCE.md`). 40-min build | yes (MoltenVK) |
| [vice-city-stories-recomp](https://github.com/OverkillLabs3/vice-city-stories-recomp) | on PSPRecomp | Vulkan HW transform | yes (MoltenVK) |
| [psprism](https://github.com/anthonyhfm/psprism) | GPL-3, C++20 | Own runtime "refract": **native Metal GE**, D3D11; Daxter playable; VFPU translated; threads, ISO9660, SAS, ATRAC3+/MP3, PSMF via FFmpeg, sceUtility via Qt. Small, AI-assisted | yes (Metal) |
| [Sifayne/psprecomp](https://github.com/Sifayne/psprecomp) | MIT, C | Complete VFPU claim, 407 HLE fns, host-thread-per-guest-thread + handoff token. Hardware probes vs real PSP 6.60: VFPU 188/201, threads 164/181, sync 234/236, savedata 86/117. Software GE, Linux | no |
| [nakagawa-recomp](https://github.com/Jstar269/nakagawa-recomp) | GPL-3 | SDL3+Vulkan, ucontext fibers, PPSSPP-derived GE/SAS kept private | no |
| [lcs-recomp](https://github.com/elmasas/lcs-recomp), [PSPRecomp-MSAE](https://github.com/coole42-pixel/PSPRecomp-MSAE) (MotorStorm Arctic Edge, racing, created 2026-10-03), [Ace-Combat-X](https://github.com/sal063/Ace-Combat-X-Recompilation) | mixed | more PSPRecomp-family ports | no |

Analysis tooling: [ghidra-allegrex](https://github.com/kotcrab/ghidra-allegrex) v21.4 (Apache-2, Ghidra 12.1.3; VFPU shown as `vadd_q(...)` calls, prefixes not modeled; `.sym` import/export with PPSSPP), [psp-ghidra-scripts](https://github.com/pspdev/psp-ghidra-scripts) (NID resolution), prxtool, rabbitizer R4000ALLEGREX, splat PSP support. Docs: [pspdev/vfpu-docs](https://pspdev.github.io/vfpu-docs/) (hardware-verified incl. prefixes, hazards, transcendental error), [PPSSPP GE docs](https://www.ppsspp.org/docs/psp-hardware/gpu/), [pspautotests](https://github.com/hrydgard/pspautotests) (real-hardware expected outputs), pspsdk headers.

Decrypted ELF: PPSSPP → Settings → Developer tools → "Dump decrypted EBOOT.BIN on game boot" → `memstick/PSP/SYSTEM/DUMP`. Keep decryption out of the repo (PSPRecomp does).

Oracle/reference: PPSSPP (GPL-2+), `Core/HLE`, `Core/Dialog`, `Core/HW`, `GPU/`. No native Metal in PPSSPP (MoltenVK). ATRAC3+ decoders: FFmpeg (LGPL) or PPSSPP `ext/at3_standalone` (LGPL-2.1).

GE hard parts on modern GPUs (from PPSSPP docs + Yakumo history): 2xSRC/2xDST/ABSDIFF blends, per-bit colour write masks, stencil-in-alpha, logic ops, framebuffer format aliasing/render-to-texture, depth swizzle, 8 KB texture cache self-texturing, CLUT4/8/16/32, PSP-specific DXT block layout (Yakumo got it wrong until PR #146), Bezier/spline patches. Metal programmable blending / framebuffer fetch should cover masks and logic ops (same trick as Bouncer's Metal backend).

Precedents: N64Recomp/Zelda64Recomp (RT64 has Metal), XenonRecomp/UnleashedRecomp (343 PPC instrs, Sept 2024→Mar 2025, Metal PR still unmerged Aug 2025). No Allegrex→LLVM work exists. Kotaku 2026-10-05: N64 recomp devs criticising AI "slopcomps", so the 2026 PSP wave deserves verification, not trust.

Implications: (1) reuse PSPRecomp for the CPU layer rather than write a translator; (2) the runtime is per game, Yakumo's `profiles/mhp3rd/host/` is the most complete MIT runtime but not a library; (3) native Metal GE is new work, psprism is the only precedent; (4) VFPU correctness and thread/timing semantics are the top CPU risks; (5) GE fidelity the top rendering risk.

## Research: Wipeout Pure facts (web, 2026-10-05)

**Correction:** the US serial is **UCUS-98612** (Greatest Hits: UCUS-98612GH), not ULUS-10007. Others: UCES-00001 EU, UCJS-10007 JP, UCKS-45008 KR, UCAS-40012 Asia, NPJG00059 JP PSN.

Versions (Redump): US v1.04 (252,968,960 B, CRC FD305564), US GH v2.00 (same size, CRC 4502C588; adds file delete, changes Zone gold/TT targets), EU 1.01 (352 MB, CRC 430725BF; 5 languages, Teasers menu, zlib WADs), JP 1.02. Modding community standardizes on **EU**; the 32bits Ghidra article used US. Cheat/patch addresses differ per version, so pin the dump's CRC on day one.

Engine: Studio Liverpool in-house, **C++** (source path `c:/Work/Wipeout/Code/System/Render/ParticleSystem_Importer.cpp` in BOOT.BIN), XML-driven (`TrackStartup.xml`, `songlist.xml`), "Dataports" runtime data binding, physics from scratch (Linklater, Game Developer Nov 2005). Lineage Fusion → Pure → Pulse → HD → 2048; `.POB` particles shared; Pure uses VEXX v4 models.

Executable: encrypted EBOOT; BOOT.BIN apparently plain (vscode-wipeout disassembles it). Stripped (researchers use `FUN_` names). Loads at ~0x08804000, code past +0x149000, data/bss past +0x313000: ~3 MB image. ~28 Sony PRX modules in `USRDIR/PRX` (mpeg, mpegbase, videocodec, audiocodec, libatrac3plus, sc_sascore, pspnet_adhoc*, libhttp/libssl/...). Data in WADs: `Data.wad`, `FE.wad`, `FEData.wad`, `Zone*.wad`, one per team.

Frame rate: Single Race/Tournament **target 60 fps** but drop (10–15 in tunnels with weapons at 222 MHz); Time Trial/Zone/Free Play **locked 30**. Limiter is a vblank spin loop (EU 0x0886509C `bnez`; 60 fps cheats: US 1.04 0x20065760, US 2.00 0x200652A8, EU 0x2006509C). Forcing 60 gives double speed in 30-fps modes: **some logic is per-frame, not per-time**. Built for 222 MHz; smoother at 333.

GE usage: 480×272; main FB 512-stride RGBA8888 at 0x04000000, depth 0x04110000; 128-wide RGB565 offscreen at 0x04154000 (+ depth 0x0415c000). **Lens flare: CPU reads the depth buffer back from VRAM** (4×4 around the sun, every other pixel, 0 = sky) → needs synchronized depth readback. **Bloom: depth memory at 0x04110000 reused as 256-wide RGBA8888 render target**, FB and old depth sampled as textures, result to 0x04132000, blended back → deliberate VRAM aliasing. Materials are GE state bits (alpha/additive blend with FIX 0xffffff + colour test, alpha test ref 0x00/0x7f, cull, clamp/repeat, depth mask); swizzled mip-mapped textures; int8/int16/float vertices with per-chunk scale. VEXX nodes: sea + reflection, skycube/cloud cube, fog cube, lens flare, dynamic shadow occluder, trails, engine flares, weather particles. PPSSPP compat flags for Pure: `SoftwareRasterDepth` (lens flare), `ForceLowerResolutionForEffectsOn` (blocky glow at high res).

VFPU: used, incl. `vscl.q` with a T prefix (GNU as cannot encode it; PPSSPP issue #464). Prefix handling must be exact.

Audio: music ATRAC3plus `.at3`; SFX likely sceSas (`sc_sascore.prx` bundled). Video: `.pmf` PSMF for FMV and in-game TV textures. Network: ad hoc 8-player, in-game browser for DLC (dead; AGRF DNS redirect, no portal confirmed).

DLC: PSP SAVEDATA folders `<GAMEID>D<PACK>` (e.g. `UCUS98612DGAMMAPACK1`) with `PI.WAD` = WAD encrypted XTEA + 256-byte signature trailer keyed per region (keys in BOOT.BIN). US packs: Gamma ×3, Delta, Classic ×3, 4 secret packs (~63 MB total). Preserved at gamezero.com and archive.org. Loading path and keys documented (thp.io/2021/pure-dlc, `vscode-wipeout` `dlc_keys.ts`). → DLC later = implement savedata-folder mounting + the game's own XTEA path; nothing exotic.

Formats documented: WAD (thp.io/2020/pure-wad; LZSS, CRC32 name hashes), VEXX v4 (thp.io/2022, vscode-wipeout MIT parses 40+ node types incl. GE render-state mapping, `Material_ApplyRenderState` at BOOT.BIN 0x62cb0), `.mip` swizzled textures, `.pob`, `.fnt`. Tools: wadutil, vextextool, Blender VEXX add-on, PureWADTool. Known addresses (US): unlock routine 0x08948870, game-state pointer 0x08B17798.

PPSSPP: Pure rated **Perfect** on US 1.04/2.00, JP, EU → strong oracle. Open issues are perf only.

Prior art: phoboslab wipeout-rewrite (PS1, 7.7k lines C from the 2022 leak), Phantom Edition (closed), PS1 wipeout-recomp (Sep 2026). **No Pure/Pulse port, decomp or recomp exists.** No Sony takedown of any Wipeout fan project found; Sony did DMCA Bloodborne patches. Keep code/assets/keys out of any public repo.

## Erik's dump (verified on disk, 2026-10-05)

`~/Downloads/Wipeout Pure (USA) (En,Fr,Es) (v2.00).iso`, 252,968,960 bytes, **CRC32 4502C588 = US Greatest Hits v2.00**, DISC_ID UCUS98612, PSP_SYSTEM_VER 1.00. 38 files:

- `PSP_GAME/SYSDIR/BOOT.BIN` 3,795,981 B: **plain ELF**, e_type 0xFFA0 (relocatable PRX), MIPS, entry 0x7238, `.text` 0x23EA44 (2.35 MB), `.rodata` 0x48260, `.data` 0x37AE9, `.bss` 0xAF474, `.rel.text` 0xB3218 (relocations present), `.ctors`/`.dtors`/`.cplinit` (C++ static init), `.symtab` 16 bytes → **stripped**. 34 `.sceStub.text.*` import sections. No decryption needed; `EBOOT.BIN` (`~PSP`) is the encrypted twin and is ignored.
- `USRDIR/Data.wad` 233.6 MB (832 entries), `FE.wad` 2.7 MB (157), `FEData.wad` 6.6 MB (240). WAD v1 (thp.io format).
- `USRDIR/PRX/` 26 Sony modules: audiocodec, libatrac3plus, sc_sascore, mpeg, mpegbase, videocodec, libfont, memab, cert_loader, libbase64, libhttp(_rfc), libparse_http/uri, libssl, ifhandle, pspnet, pspnet_adhoc, _adhoc_auth, _adhoc_download, _adhoc_matching, _adhocctl, _ap_dialog_dummy, _apctl, _inet, _resolver.
- `USRDIR/DevMenu.cfg`: a developer-menu config. Switches include Load Frontend, Track/Team/Class/Mode, Network Client, Camera Mode, Cut-down graphics, "Emulate PSP polygon clipping", Draw Collision Data, Draw Simulation, Show AI race speeds, AI FPS 60, Autopilot, per-weapon toggles, **FPS TTY / File TTY / Network TTY** (printf-style logs exist), Music/Sound. → The dev menu and TTY are first-class debugging levers; find the TTY sink early.
- `ICON1.PMF`, `SND0.AT3` (PSMF and ATRAC3+ in the XMB assets, confirming the codecs).

### BOOT.BIN import table (verified from the ELF)

Module `WO_Game` v1.01. 33 libraries, **278 imported functions**: ThreadManForUser 51, sceHttp 32, sceMpeg 23, sceUtility 21, sceSasCore 18, IoFileMgrForUser 18, sceGe_user 10, sceAudio 9, UtilsForUser 9, sceAtrac3plus 8, sceRtc 7, sceNetApctl 7, sceNetAdhoc 7, sceUmdUser 6, sceNetAdhocctl 6, sceNet 5, ModuleMgrForUser 5, sceDisplay 4, sceSuspendForUser 3, sceCtrl 3, SysMemUserForUser 3, StdioForUser 3, LoadExecForUser 3, Kernel_Library 3, then 1–2 each: sceWlanDrv, sceSsl, sceNetResolver, sceNetInet, sceNetAdhocMatching, scePower, sceParseUri, sceParseHttp, sceOpenPSID. Network + HTTP ≈ 70 functions → stubbed in v1 (browser dead anyway; adhoc later). **v1 HLE surface ≈ 210 functions**, most already in Yakumo's profile.

291 embedded source paths (`c:/Work/Wipeout/Code/Backend/General/*ModeManager.cpp`, `*RaceManager.cpp`, `System/Render/*`, `c:/Work/Studio/Framework/lzss.cpp`, ...) → assert/log strings can label functions by source file, as Bouncer's `label_functions.py` did.

## Research: candidate bases inspected (web, 2026-10-05)

| | PSPRecomp (MIT) | Yakumo (MIT, fork of PSPRecomp) | psprism (GPL-3) |
|---|---|---|---|
| Framework core | `src/` 3.3k + `include/` 2.5k + `tools/codegen_main.cpp` 1.6k lines | `src/` 5.2k (adds `interpreter.cpp` 1.1k), `include/` 2.8k, codegen 2.1k, tests 3.3k; adds `set_runtime_missing_function_hook`, `set_runtime_unsupported_hook`, `Runtime::unregister_functions` | translator 3k, runtime 1.4k, 434 one-file-per-function stubs |
| macOS | **none** (all host code behind `_WIN32`, MSVC flags, DX12) | **yes**: clang/Apple silicon, SDL3, MoltenVK, `.dmg` release, `brew install cmake ninja python ccache pkg-config sdl3 molten-vk vulkan-loader vulkan-headers glslang` | yes, native Metal in `macos_frontend.mm` (1.8k lines, shaders compiled from source string) |
| Interpreter fallback | **no** (`rt.unsupported` halts) | yes | yes |
| Codegen | `psp_analyze <ELF>` → seeds CSV; `psp_recomp <ELF> --auto <dir>`; seeds from entry, `jal` targets, code pointers in data/relocs; units by address span | same + overlays as dlopen'd shared libs | own |
| VFPU | translated to C++ with prefixes (`vpfxs/t/d` → `vfpu_ctrl`, source/dest prefix helpers, peephole `_ct` variants). **Gaps:** opcodes 0x35/0x3D (lv.l/lv.r/sv.l/sv.r) and unlisted sub-ops (vsrt, vbfy, vt4444/5551/5650, vrnd, vmfvc/vmtvc) decode generic → halt | same gaps in codegen (adds vsgn, vsocp); interpreter handles prefixes | support table incl. 0x35/0x3D; helper call when prefixes non-identity |
| Kernel | one host thread, contexts swapped in HLE, virtual clock `virtual_time_us`, starvation hook | `kernel/` 2.2k: one emulation thread, deterministic virtual clock held to real time, blocking import saves ctx (pc=$ra, v0=result). **`sceDisplayWaitVblankStart` not registered** (MHP3rd paces via `sceCtrlReadBuffer`) | one host thread per guest thread, FIFO ticket lock, **wall-clock** waits |
| GE | `ge_renderer.cpp` 5k (SW raster) + free-function backend API, DX12 only | `gpu/` 17k: `ge_state.*` parses display lists → backend-neutral `DrawCall`/`BlockTransfer`; CPU texture decode (5650/5551/4444/8888, CLUT4-32, DXT1/3/5, swizzle); skinning 8 bones, morph, 4 lights, fog, blend, depth/alpha test, stencil; GLSL uber-shader; one offscreen target per guest FB; **no logic ops, no Bézier/spline**; `VulkanRenderer` concrete class owning SDL window/input/ImGui | CPU-transformed vertices → `submit_ge_primitive`; one Metal texture per VRAM address; no fog/Bézier/morph/logic ops |
| Audio | waveOut-style | SDL3 `SDL_AudioStream`; sceAudio 7 fns (only `OutputPanned[Blocking]`); sceSasCore 14 (32 VAG voices, no reverb); sceAtrac3plus 12 via FFmpeg (built from source: atrac3, atrac3p, h264 only, shared, LGPL) | at3_standalone (LGPL) |
| Game-specific glue | all 226 HLE fns in `vcs_profile.cpp` (10.5k lines) | `hle/` 5.8k with MH hooks (58 refs), `camera/` 44 hardcoded addresses, `mods/`, `ui/` 11.6k. Issue #99: split framework into **TeamGDB/PortableKit** (exists, MIT, pushed 2026-09-30, not inspected) | n/a |
| Build | MSVC >2 GB/unit | MHP3rd 362k instrs → 89 units, 12–14 min on M1 8 GB; parallel capped 1 per 4 GiB; any `include/psprecomp/` edit = full rebuild; 64 MiB main-thread stack (re-exec with larger RLIMIT_STACK) | `make` |
| Agent docs | none | `AGENTS.md`, `CLAUDE.md`, 9 CI workflows | none |

Takeaways: base on Yakumo's framework; lift `kernel/`, `hle/` (threadman, sysmem, io, system, atrac, mpeg, savedata, minus MH hooks), `audio/`, `movie/`, `save_data/`, `gpu/ge_state.*`, `gpu/texture_decode.*`; replace `vulkan_renderer.cpp` by a backend interface with Metal (ours) and Vulkan (theirs, split from SDL/ImGui) implementations. Check PortableKit first: it may already be the split. Wipeout's 2.35 MB `.text` ≈ 590k instructions → expect ~20 min full codegen+build on the M4 Pro, so keep `include/psprecomp/` stable and give Opus tasks incremental build targets.

