# The upstream list

What of the vendor patch series (`patches/`, one patch per topic since task 052, 2026-10-07) could go to
TeamGDB/PortableKit, what each pull request would carry, and what it needs first. Nothing has been offered upstream
yet, and offering it is Erik's call: this repo never pushes (CLAUDE.md). The series is cut against the pin, 8b0c3fe
(2026-09-27); PortableKit says its interfaces change without notice (D-001), so each pull request would be rebased
onto upstream's head first, and upstream's head (and Yakumo, the read-only reference of D-001) checked for the same
fix before writing one.

## Dependencies
"Applies" was tried in task 052: each patch with `git apply` on a clean checkout of the pin, alone and then on top of
what it names. "Builds" is read from the code (no patch was built on its own): which earlier patch defines something
it uses.

| Patch | Applies to the pin alone | Needs, to apply | Needs, to build |
|---|---|---|---|
| 0001-cmake-embed-nids-verbatim | yes | nothing | nothing |
| 0002-ge-state-commands | yes | nothing | nothing |
| 0003-vulkan-renderer-fixes | yes | nothing | 0002 (`DrawCall::stencil` and the write masks) |
| 0004-ge-backend-and-shell-seams | no | 0003 (`hle_media.cpp`, the renderer header) | 0002 (the record format writes every `DrawCall` field), 0003 (the depth write-back it routes) |
| 0005-kernel-host-waits-and-pacing | no | 0004 (one line, where the HLE makes the shell) | 0004 |
| 0006-mpeg-ring-not-empty-while-aus-pending | yes | nothing | nothing |
| 0007-savedata-list-and-no-key-mode | no | 0004 (the shells' script readers) | 0004 |
| 0008-sas-reverb | yes | nothing | nothing |
| 0009-vfpu-rounding | yes | nothing | nothing |

The patches as they were before task 052, one per task, are in this repo's history (`patches/` at commit 743623f, the
brief of task 052) and give the finer steps that several pull requests below would be cut along.

## Each patch

### 0001-cmake-embed-nids-verbatim: candidate
A pull request of one word: `VERBATIM` on `portablekit_add_game`'s NID embedding command, with the case that breaks
without it (a profile that ships `config/nids.csv`, so the command gets `-DINPUT=a.csv|b.csv` and the shell takes
the `|` for a pipe). Needs nothing. The smallest and safest of the list, a good first contact.

### 0002-ge-state-commands: candidate
`GeState` parses commands it ignored into `DrawCall`: the stencil test and operations and the two write masks; the
texture map mode and the shade lights; mip levels 1 to 7, the level count, TEXLEVEL and TEXLODSLOPE; the colour test,
dithering and CLIPENABLE. Only `ge_state.{hpp,cpp}`; it changes nothing a backend draws until the backend reads the
fields, so it is safe on its own and is what any backend fix for these commands needs first. Could go as one pull
request or as four (old 0004, 0013, 0014, 0017's ge_state sections, in that order). The comments name Wipeout Pure's
draws as examples; keep or trim them.

### 0003-vulkan-renderer-fixes: candidate
Six fixes to the Vulkan renderer, better offered as separate pull requests than as one:
- the framebuffer texture that starts at the texture's address wins over one that only contains it (old 0003):
  applies to the pin alone;
- the alpha test's function numbers as the GE's (0 NEVER, 1 ALWAYS; old 0005): the most valuable here, since every
  game that enables the alpha test with ALWAYS loses those draws; as cut it sits on the stencil-as-alpha lines and
  does not apply to the pin, so its pull request is a hand rebase of a few lines;
- the targets' descriptor sets freed before their pool at shutdown (old 0007): a heap corruption under MoltenVK; as
  cut it sits on the dual-source lines, so again a short hand rebase;
- stencil as alpha (old 0004's renderer part), then the real stencil attachment, shadow volumes and dual-source
  blending (old 0006): need 0002's stencil fields; together the largest part (pipeline key and keys file version 3,
  the stencil-to-alpha resolve, a SPIR-V edit for pipelines without dual source);
- depth written back to guest VRAM at a GE SIGNAL (old 0008): applies to the pin alone, but costs a GPU wait (about
  1 ms a race frame here) in every game; upstream would want it behind a `GameProfile` switch, off by default, which
  the pull request would add.
The three comments from old 0013, 0014 and 0017 (what this renderer does not draw) go with whichever request carries
the matching 0002 fields, or nowhere.

### 0004-ge-backend-and-shell-seams: candidate, the largest; talk to upstream first
The HLE's interface to whatever draws and shows the GE's work (D-003, D-007): `gpu::GeBackend` with its registry and
the vulkan, null and record backends; `host::Shell` with its registry and the vulkan and headless shells; the SDL pad,
the gamepad mapping and the input script's grammar moved out of the renderer; ImGui's platform init moved into the
shell (old 0012, which a non-Vulkan shell needs). 32 files, about 215 KB. This is what lets a game add a backend or a
shell in its own sources (our Metal backend and shell in `src/`, D-008), and what a headless run needs; it touches
`hle_media.cpp`, the renderer and `host/ui/` broadly, so it is the request most likely to need rework on upstream's
head. Offer it as an issue describing the two seams before any code, then as at least three requests: the GE backend
seam with the null backend; the shell seam with the headless shell and the UI platform init; the record backend and
its format, which serve our A/B tooling (`tools/gerec/`, `src/tools/ge_replay`) and may well stay ours. The format's
readers for Draws that end early exist only for recordings our own builds made before old 0013, 0014 and 0017; an
upstream request would write the full Draw and drop them, with the comments that cite those patch numbers.

### 0005-kernel-host-waits-and-pacing: candidate
Two parts. The kernel part (`kernel.{hpp,cpp}`, `hle_adhoc.cpp`: only waits for the network let real time pass in an
unpaced run) applies to the pin alone and makes every headless run about a hundred times faster; offer it first, on
its own. The pacing part (`Kernel::set_paced`, called where the HLE makes the shell) follows the shell seam; without
the seam it would be called wherever upstream decides that a run has no window.

### 0006-mpeg-ring-not-empty-while-aus-pending: candidate
`hle_mpeg.cpp` only, applies to the pin alone, needs nothing: `sceMpegRingbufferAvailableSize` stays one packet short
of empty while the demuxer still holds access units, so a game that ends its movie on an empty ring keeps its last
pictures. A small, self-contained request.

### 0007-savedata-list-and-no-key-mode: candidate
Two requests. The no-key mode (old 0019: a save without a game key written and checked in the save-data utility's
mode 1, as a PSP and PPSSPP do; `data_file_hash` over unpadded files) applies to the pin alone and needs nothing; it
carries no key material, every key comes from upstream's own `crypto_keys()` by slot. The save list (old 0015: list
requests answered from the input script, a PSP-style dialog over the game, or a safe default) needs the shell seam
for its `save` script step in the headless shell, and the interface layer for the dialog.

### 0008-sas-reverb: candidate
The SAS reverb unit and the voices' effect sends: `sas_core.{hpp,cpp}` and the `__sceSasRev*` calls and
`__sceSasSetVolume`'s sends in `hle_media.cpp`. Applies to the pin alone, needs nothing. Written from psx-spx's public
documentation, no PPSSPP code. Two departures from the SPU (stepping at 44100 Hz, sends at half volume) were measured
against PPSSPP's output of one game; the request should say so, and the SPU's own rate and filters stay a switch
(`<prefix>_SAS_REVERB_SPU_RATE=1`).

### 0009-vfpu-rounding: the rules are candidates, the test mode is ours
The PSP's rounding for VFPU dot products (pspautotests' rule) used by `vdot`, `vhdp`, `vcrsp`, `vqmul`, `vtfm`,
`vmmul`, the cross product's lanes and `vfad`/`vavg`, and `-ffp-contract=off` for the generated units, without which
clang fuses across translated instructions. Applies to the pin alone (old 0020 does; old 0021 needs it). Ours, and to
be cut out by hand before any request: `vfpu_dot_mode()` and its PPSSPP branches (`vfpu_dot_ppsspp`, the test-mode
branches of `vfpu_cross_dot` and `execute_vfpu_horizontal`), which exist for our scorecard's comparisons with PPSSPP
(D-013) and sit inside the same functions as the rule, so no patch boundary can separate them. It changes
`include/psprecomp/` and the code generator: every game's corpus recompiles and its results move by an ulp wherever
clang had fused, so the request carries the measurements (task 047, pspautotests' cases).

## Ours only
No patch is ours only. Inside them, what would not go upstream: the VFPU test mode (0009); the record format's
readers for early recordings (0004); comments that cite this repo's tasks, fidelity differences and old patch
numbers. If a future patch is ours only (a test hook, a seam only our profile uses), it stays a patch of its own so
that this list stays true.

## An order to offer them in
0001; 0006; the kernel part of 0005; 0002; the standalone renderer fixes of 0003 (exact target, alpha test numbers,
shutdown order); 0008; the rules of 0009; the stencil, shadow volume and dual-source part of 0003; 0007's no-key
mode; the seams of 0004, after the issue; the pacing part of 0005 and 0007's save list after them; the depth
write-back of 0003 behind a profile switch.
