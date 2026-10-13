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
| 0016-menu-rows-by-capability | no | 0004 (`host/shell/shell.hpp` is new there; tried in task 064 with `patch` on the pin plus 0003 and 0004) | 0004 (`host::Shell`, the menu's `shell()`) |
| 0017-internal-scale-by-backend | no | 0004 (`host/gpu/ge_backend.hpp` and `vulkan_ge_backend.cpp` are new there), 0016 (the menu's lines it changes, its `restore` gate) | 0004 (`gpu::GeBackend`, `active_backend()` in `hle_media.cpp`) |
| 0018-vulkan-effects-at-1x | no | 0002 to 0004 and 0010 to 0015 (the renderer lines it changes; tried in task 068 on the pin: it applies on those, not on 0002 to 0004 alone) | 0003 (the framebuffer textures, the depth write-back), 0004 (`display_image`), 0012 (the mip rule), 0014 (the 16-bit pixel scale), 0015 (the placement) |
| 0019-game-option-rows | no | 0016 and 0017 (the menu, profile and settings lines it sits beside; tried in task 070 on the pin plus 0003, 0004, 0016 and 0017: it applies, and not without 0017) | 0016 (`choice_row` through the dump's `ChoiceRow`) |
| 0020-vulkan-texture-detail | no | 0012, 0015, 0018 and 0019 (the renderer, ge.frag and profile lines it edits; read from the code in task 076, not tried patch by patch) | 0012 (`mip_levels`, the level rule), 0018 (`drawn_extent`), 0019 (`settings::game_option`) |
| 0021-content-packs | no | 0016 (the menu lines around the save rows that it adds its section after, `dump_row("[save rows]")`; tried in task 078 with `patch` on the pin plus 0003, 0004 and 0016: it applies) | 0016 (`dump_row`, `dump_detail` and the dump's row objects) |
| 0027-window-size-switch | yes (tried in task 084 with `git apply --check` on a clean checkout of the pin) | nothing | nothing |
| 0028-vulkan-orthographic-fit | no | 0010 and 0020 (the transform and summary lines, the `orthographic` flag it moves; read from the code in task 085, not tried patch by patch) | 0010 (`viewport_into_clip` in the transform and the summary) |

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

### 0016-menu-rows-by-capability: candidate
The Esc menu draws a row only when its feature exists (D-014): `GameProfile::features` (`MenuFeatures`: ad hoc play,
the right-stick camera, the mouse camera) and five `Shell` virtuals (`supports_frame_interpolation`,
`supports_perf_overlay`, `supports_aspect`, `supports_touch`, `api_name`). Every default is today's, so the
framework's games and its Vulkan shell draw every row they drew before (task 064 checked it with the Vulkan shell's
dump and every flag true); a port with a game that lacks a feature, or a shell of its own, sets the answers. Needs
the shell seam (0004), so it follows that request. `<prefix>_MENU_DUMP` (the rows of each tab printed when the menu
opens) is test tooling any port's checks could use; it routes the menu's rows through function objects in
`menu.cpp`, which upstream may prefer as a hook in `widgets.cpp`'s shared row code, where it would also list the
rows the font, texture-pack and save screens draw.

### 0017-internal-scale-by-backend: candidate
The menu's Resolution row asks the GE backend the HLE draws with (`gpu::running_backend()`) rather than the Vulkan
renderer: `GeBackend::supports_internal_scale()`, `set_internal_scale(setting)` and `target_size()`, with defaults
that leave the row out (no, nothing, 480x272) and a Vulkan backend that answers yes and forwards to its renderer, which
is what the menu called before, so the framework's games and the Vulkan shell show the same rows. A backend of a port's
own (our Metal one) then gets the row by answering. With it, `GameProfile::default_internal_scale` (unset: the
framework's 2), for a game whose renderer draws a higher default well; `settings::defaults_for` applies it. Needs the
backend seam (0004) and follows 0016, whose menu lines it edits; offer it with or after 0016.

### 0018-vulkan-effects-at-1x: candidate, behind a profile switch
Each Vulkan target is made at the size its stride gives: the internal resolution for a buffer at least 480 pixels
wide, 480x272 for a narrower one; every pass, viewport, scissor, copy, blit and read-back takes the target's own size;
the frame write-back and `read_back_framebuffer` give the guest the centre pixel of each block, as the depth
write-back did. The size per target is a fix any game could take (the display blit, the captures and the read-backs
no longer assume one size). The rule itself suits this game (its bloom is drawn in 256-wide buffers and its adverts in
a 128-wide one, which the PSP and PPSSPP's "lower resolution for effects" keep at 480x272) but would cost a game whose
narrow targets want the scale (a mirror, a scene drawn to a texture and shown large), so upstream would take it as a
`GameProfile` field or a setting, as PPSSPP keeps it a per-game flag. Needs the Vulkan patches before it (0003, 0004,
0010 to 0015); offer it after them.

### 0019-game-option-rows: candidate
A game's own settings as rows of the menu: `GameProfile::options` (`GameOption`: key, label, choices, help text,
default, tab), stored as `game.<key>=<index>` in settings.ini with `<prefix>_<KEY>` deciding one run, read by the port
with `settings::game_option(key)`, and drawn in a Game section at the end of the tab each names, restored with the
tab's defaults. No option, nothing changes, so the framework's games are untouched. Any port with an enhancement or a
per-game choice the framework does not know (a frame-rate unlock, a skip of an intro, a fix with an off switch) can
use it instead of an environment variable alone. Needs 0016's menu lines (the dump's row objects) and applies on 0017;
offer it after them. Upstream may prefer the value as text (the choice's own name) rather than an index in the file.

### 0020-vulkan-texture-detail: candidate, behind a profile field
Texture detail at the internal scale (D-019): a game names, in `GameProfile::texture_detail_option`, the game option
(patch 0019-game-option-rows) whose choice 1 asks the renderer to pick each mipmapped 3D draw's level for the pixels drawn rather than
the PSP's (the level constant lowered by 16 x log2 of the internal scale, whatever the GE's rule) and to sample it
through `textureGrad` with an anisotropic sampler (`samplerAnisotropy` when the device has it). Null by default, so the
framework's games are untouched; with the option off the path is the old one to the pixel. Any port drawn above 1x
gains from it. Needs 0012, 0018 and 0019.

### 0021-content-packs: candidate
Content packs as a kind of save folder (task 078): a profile marks a folder the game loads as content, such as a
download pack (`SaveFolder::content_pack`), and names the System tab's section for them
(`GameProfile::content_packs_label`), which shows how many the memory stick holds, each by name, and a row that opens
Import's folder browser (`ui::open_import()`); Export and Back up saves leave content packs out; and Import skips, for a
content pack only, a SAVEDATA_FILE_LIST entry that is not a printable name, which seven of Wipeout Pure's twelve US
download packs carry (consoles took them). Nothing marked and no label: every screen, export, backup and import check
is as before, so the framework's games are untouched. Any port of a game with download content gains a place for it
that is not the saves. Needs 0016's dump rows; offer it after 0016. Upstream may prefer the relaxation as a flag of its
own rather than tied to `content_pack`, and the count's text from the profile.

### 0027-window-size-switch: candidate (tooling)
`<prefix>_WINDOW_SIZE=WxH` opens the Vulkan renderer's window at that size instead of 480x272 times the window
scale (task 084), so a check can run a window of another shape, such as the 21:9 of `tools/aspect_check.sh`; unset
or malformed, nothing changes. Any port's window checks can use it. Applies to the pin alone; offer it with the
tooling.

### 0028-vulkan-orthographic-fit: candidate
Under Fill, the renderer's interface fit takes the 2D draws a game makes in 3D mode too: transformed, orthographic,
lighting off (task 085). Their clip x and y are scaled about the screen's centre after `viewport_into_clip`, in the
transform and in the interpolation summary alike; a draw at least 470 PSP pixels wide stays spread, as the through
rule has it. Any game whose menus or HUD are orthographic draws (Wipeout Pure's all are) keeps its 2D at square pixels
under Fill; a game whose 2D is through mode sees no change. `<prefix>_NO_ORTHOGRAPHIC_FIT` restores the through-only
fit. Needs 0010; offer it after 0010 and 0020. The width rule cannot tell a screen-wide layer of interface art from a
backdrop (Wipeout Pure's profile screens draw their panel as one full-screen quad), which upstream may want answered
before it takes the rule.

## Ours only
No patch is ours only. Inside them, what would not go upstream: the VFPU test mode (0009); the record format's
readers for early recordings (0004); comments that cite this repo's tasks, fidelity differences and old patch
numbers. If a future patch is ours only (a test hook, a seam only our profile uses), it stays a patch of its own so
that this list stays true.

## An order to offer them in
0001; 0006; the kernel part of 0005; 0002; the standalone renderer fixes of 0003 (exact target, alpha test numbers,
shutdown order); 0008; the rules of 0009; the stencil, shadow volume and dual-source part of 0003; 0007's no-key
mode; the seams of 0004, after the issue; the pacing part of 0005, 0007's save list, 0016, 0017, 0019, 0020 and 0021
after them; the depth write-back of 0003 behind a profile switch.
