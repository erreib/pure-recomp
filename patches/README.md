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
| 0005-alpha-test-never-always | Bug | The fragment shader read the GE alpha-test function 1 as NEVER and 0 as "no test", but the GE numbers them like the depth test, 0 NEVER and 1 ALWAYS, so every draw that enables the alpha test with ALWAYS was discarded: on Vineta K that is 268 of 871 draws and 87% of the frame (track, barriers, arches, pillars, sky cube). Tests by the GE numbering, pushes ALWAYS for draws without the test and for clears, and compiles the discard out for ALWAYS instead of NEVER. Applies after 0003 (written before 0004 existed). Upstream candidate |
