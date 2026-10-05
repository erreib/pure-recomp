# Patches against the vendored framework

Applied in numeric order by `tools/vendor_setup.sh` (`git apply` inside `vendor/yakumo`). `tools/patches.sh check`
applies the series to a clean checkout of the pinned commit and compares it with the vendor tree;
`tools/patches.sh export NNNN-slug` writes a new patch from the vendor tree's uncommitted changes.

| Patch | Kind | Why |
|---|---|---|

Kinds: Layout constant, Bug, Missing feature, Tooling, Speed. Patches that could go upstream are marked in the Why column.
| 0001-embed-nids-verbatim | Bug | `portablekit_add_game` passes `-DINPUT=a.csv|b.csv` to the shell unquoted when a profile ships `config/nids.csv`; the `|` becomes a pipe. Adds `VERBATIM`. Upstream candidate |
| 0002-ring-not-empty-while-aus-pending | Bug | `sceMpegRingbufferAvailableSize` reported the ring empty while the demuxer still held access units (the audio fetch runs ahead and takes the last packs), so a game that ends a movie on an empty ring (Wipeout Pure) dropped its last 16 pictures and never tore the movie down. Reports one packet short of empty while units are queued. Upstream candidate |
| 0003-framebuffer-texture-prefers-exact-target | Bug | `find_framebuffer_texture` picked the most recently drawn target containing a texture's address; Wipeout Pure's bloom blurs 0x04132000, which lies inside the 0x04110000 target, so the blur sampled never-drawn rows (magenta). Prefer a target starting at the address. Upstream candidate |
| 0004-stencil-as-alpha | Missing feature | The GE state ignored the stencil (0x24, 0xDC, 0xDD) and the write masks (0xE8, 0xE9), and every draw stored its fragment alpha, so Wipeout Pure's bloom mask (stencil REPLACE into the 8888 alpha) was full everywhere and the whole race scene bloomed. Parses them into `DrawCall::stencil`, `color_write_mask`, `alpha_write_mask`; the target's alpha is now written only by the stencil zpass op (REPLACE ref, ZERO; KEEP, no stencil test or masked bits leave it), through the fragment shader or, when the colour blend reads source alpha, the alpha blend factors (exact for ZERO, opaque fragments only for REPLACE); whole masked colour channels are not written. Other stencil functions and INCR/DECR/INVERT are logged once. `PURE_NO_STENCIL_ALPHA=1` restores the old path. Upstream candidate |
