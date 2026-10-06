# 021: The GE backend seam: interface, null and record backends, Vulkan adapter

Milestone: M6 | Branch: task/021-ge-backend-seam | Status: OPEN

## Goal
Introduce `portablekit::gpu::GeBackend` (docs/ge-backend.md section 1) as vendor patch 0009, adapt the existing
Vulkan renderer to it without changing its output, and add the `null` and `record` backends. Selection by
`PURE_GE_BACKEND=vulkan|null|record` (default vulkan). The regression suite must give the same fractions before and
after.

## Read first
- CLAUDE.md, docs/ge-backend.md (the contract), docs/decisions.md D-003, docs/ge-effects.md,
  vendor/portablekit/host/gpu/vulkan_renderer.hpp (the public interface), host/hle/hle_media.cpp (every
  `renderer.`/`renderer->` call: the seam's call sites), host/gpu/ge_state.hpp (DrawCall, BlockTransfer),
  patches/0003-0008 (behaviour the adapter must keep), ~/dev/bouncer-recomp/src/gs/null_backend.cpp and
  patches/0020-gs-backend-recording.patch there (the shape of null and record backends; read-only)

## Deliverable
1. `host/gpu/ge_backend.hpp`: the interface from docs/ge-backend.md, `BackendConfig`, `PresentedImage` (an opaque
   handle the shell understands per API: for Vulkan the existing image/view the present path already uses), a
   registry (`register_backend(name, factory)`, `make_backend(name)`), and the selection by `<prefix>_GE_BACKEND`.
2. `VulkanGeBackend`: forwards to the existing renderer's draw/transfer/read-back/write-back/upload/capture/stats
   methods. The shell (the rest of VulkanRenderer) calls the backend through the interface for those operations.
   Keep the change mechanical; no behaviour change.
3. `null_backend.cpp`: accepts everything, presents a black image, counts draws; the game must run through the
   frontend route headless with `PURE_GE_BACKEND=null` (`PURE_NO_RENDER` unset) at > 200 fps.
4. `record_backend.cpp`: wraps the selected inner backend (`PURE_GE_RECORD_INNER`, default vulkan); writes
   `PURE_GE_RECORD=<file>` from frame `PURE_GE_RECORD_AT` for `PURE_GE_RECORD_FRAMES` frames: a versioned stream of
   DrawCall/BlockTransfer/upload/read-back/write-back events with their guest-memory inputs (vertices, indices,
   textures, CLUTs, the ring of VRAM words a draw reads) and the presented image per frame (BMP). A `gerec_dump`
   tool (C++ in the vendor tools or Python in tools/gerec/) lists a recording's events.
5. Patch 0009 via `tools/patches.sh export`, README rows, a section in docs/ge-backend.md "What landed".

## Acceptance criteria
- [ ] `tools/frame_regress.sh` (task 020) passes with the same fractions (+/- 0.005) as before the patch.
- [ ] `PURE_GE_BACKEND=null` frontend route runs headless to frame 2000 and reports draws submitted.
- [ ] A 3-frame recording of the race at frame 6016 (`PURE_GE_RECORD_AT=6014 PURE_GE_RECORD_FRAMES=3`) is written and
      `gerec_dump` lists its events with counts that match `[render] frame ... (N draws)`.

## Verify
`tools/patches.sh check && tools/frame_regress.sh && PURE_GE_BACKEND=null python3 tools/run_boot.py --frames 2000 --seconds 120 --env PURE_NO_RENDER= out/021/null.log && grep -q 'draws' out/021/null.log`

## May touch
- vendor/portablekit/host/gpu/ and host/hle/hle_media.cpp via `tools/patches.sh export 0009-<slug>`, patches/,
  tools/gerec/ (new), docs/ge-backend.md, README.md

## Must not touch
- vendor/portablekit/include/psprecomp/, src/, tools/run_boot.py, tools/imgdiff.py, config/, patches/0001-0008

## Estimated turns
70

## Escalate when
The Vulkan adapter cannot keep the output identical without restructuring the renderer's frame loop (report what the
loop assumes), or the shell cannot run without a window for the null backend (report the dependency).

## Result
Status: PARTIAL. The seam, the Vulkan adapter, null, record, gerec_dump and patch 0009 are done, and all three
acceptance criteria and the Verify line pass. Two things in deliverable 3 are not met, and neither can be fixed inside
this brief's limits. First, null runs headless at about 19 frames a second, not > 200: the kernel's host-wait sleep
holds it there, as it holds a plain `PURE_NO_RENDER=1` run (open question 1). Second, the frontend route's presses
cannot reach a game running without a window, because the pad and the input script belong to the window shell (open
question 2).

Changed:
- `patches/0009-ge-backend-seam.patch` (new, 1722 lines). It touches these files under `vendor/portablekit/`:
  - `host/gpu/ge_backend.hpp`, `ge_backend.cpp` (new): the interface, the registry and the selection.
  - `host/gpu/vulkan_ge_backend.cpp` (new): the Vulkan adapter, built with the renderer sources.
  - `host/gpu/null_backend.cpp`, `record_backend.cpp`, `ge_record_format.hpp` (new): built with the system-layer
    sources, so they also build without Vulkan. They pass a syntax check with `PORTABLEKIT_HAS_RENDERER` undefined.
  - `host/gpu/vulkan_renderer.hpp`, `vulkan_renderer.cpp`: one new const method, `display_image(address)`.
  - `host/hle/hle_media.cpp`: every GE call now goes through the backend. `ensure_backend()` makes the backend and
    the shell.
  - `cmake/PortableKit.cmake`: the four new sources. This file is outside "May touch", but the new files cannot be
    built without it.
- `patches/README.md`: the 0009 row.
- `tools/gerec/gerec_dump.py` (new).
- `docs/ge-backend.md`: new section 6, "What landed".
- `README.md`: rows for `PURE_GE_BACKEND` and `PURE_GE_RECORD*`, and a Layout row for `tools/gerec/gerec_dump.py`.
- This file.
- Commits: `1f60e05` (the seam) and the Result commit.

The interface as landed (`portablekit::gpu`, `host/gpu/ge_backend.hpp`):
```
struct BackendConfig { VulkanRenderer *vulkan_shell; std::uint32_t internal_scale; bool sharp_textures; };
enum class ImageApi : std::uint8_t { None, Cpu, Vulkan, Metal };
struct PresentedImage { ImageApi api; std::uint32_t address, width, height; const std::uint8_t *pixels;
                        std::uint64_t image, view; bool valid() const; };
class GeBackend {
  const char *name() const; bool needs_window() const;                  // asked before initialize()
  bool initialize(const BackendConfig &, std::string &error); void shutdown();
  void begin_frame(); void begin_display_list();
  bool gpu_decode() const; bool check_gpu_decode() const;               // GeState::set_raw_vertices
  void submit(const DrawCall &, const GuestMemory &);
  void block_transfer(const BlockTransfer &, GuestMemory &);           // before the HLE copies the rows
  void write_back_frame(GuestMemory &); void read_back_framebuffer(std::uint32_t, GuestMemory &);
  bool write_back_depth(std::uint32_t color, std::uint32_t depth, std::uint32_t stride, GuestMemory &, const char *why);
  void upload_frame(std::uint32_t display, const std::uint8_t *, std::uint32_t w, std::uint32_t h, std::uint32_t stride);
  PresentedImage present_image(std::uint32_t display_address);
  bool capture_frame(const std::string &path);
  std::uint64_t draws_submitted() const; std::uint64_t frames_presented() const;
};
void register_backend(std::string name, BackendFactory, std::string description = {});
std::unique_ptr<GeBackend> make_backend(std::string_view name);
std::vector<std::string> backend_names(); std::string selected_backend();   // <prefix>_GE_BACKEND, default vulkan
struct BackendRegistration { BackendRegistration(const char *name, const char *description, BackendFactory); };
```
- Differences from section 1 of the contract:
  - `block_transfer` takes a non-const `GuestMemory`, because the read-back writes it.
  - `name`, `needs_window`, `gpu_decode` and `check_gpu_decode` are new.
- How `present_frame` drives a flip: `upload_frame` when the framebuffer is in RAM, the interface,
  `write_back_frame`, `present_image`, then the shell's `VulkanRenderer::present`, the optional capture, and
  `begin_frame()` for the next frame.
- What stays fused in Vulkan: the renderer still begins its frame lazily and ends it inside its own `present()`. So
  `VulkanGeBackend::begin_frame()` does nothing, and `present_image()` only names the target that `present()` shows.
  Every other method forwards to the method the HLE called before, with the same arguments, at the same point. That
  is why the output did not change and the escalation case did not occur.
- Selection:
  - `PURE_NO_RENDER` with the default `vulkan` still means no rendering at all.
  - `null` needs no window. With `PURE_NO_RENDER` set (even to nothing), it runs headless with no GPU.
  - Without `PURE_NO_RENDER`, `null` opens the window and shows black, and scripted input works.
  - An unknown name prints the registered names and falls back to vulkan.

Suite numbers (`tools/frame_regress.sh`; before on 25a7041, after on the patched tree):

| Scene | Before | After | Verify run (commit 1f60e05) | Captures, before vs after and Verify |
|---|---|---|---|---|
| lang | 0.0544 | 0.0544 | 0.0544 PASS | identical (0 of 522240 px) |
| title | 0.0302 | 0.0302 | 0.0302 PASS | identical |
| profile | 0.0543 | 0.0543 | 0.0543 PASS | identical |
| main_menu | 0.0331 | 0.0331 | 0.0331 PASS | identical |
| race_hud | 0.0672 | 0.0672 | 0.0672 PASS | identical |

All three suite runs gave delta +0.000 on every scene and took 7m 7s to 7m 8s. The captures were compared with
`imgdiff.py --tol 0`, and both the after captures and the Verify captures match the before captures pixel for pixel.

null (Verify run, headless):
- `[render] null backend: 2000 frames, 19615 draws submitted, ...` in about 106 s.
- A plain `PURE_NO_RENDER=1` run to frame 2000 takes the same time.
- `PURE_PERF=log` shows render time 0.0 ms. The process uses about 4% of one core, about 2 ms of CPU a frame.

record (acceptance 3). The run: `main_menu.txt` + `single_race.txt` on an empty stick, `--every 3007`,
`PURE_GE_BACKEND=record PURE_GE_RECORD=out/021/race.gerec PURE_GE_RECORD_AT=6014 PURE_GE_RECORD_FRAMES=3`, Vulkan
inner.
- The file is 23.4 MB, with 4250 records.
- `gerec_dump.py` exits 0, and every Draw parses to its exact size:

```
  frame  draws   said   submitted  delta  records  memory      bytes    image  check
   6014    906    906      343736    906     1595     292    4842432  1566774  ok
   6015    905    905      344641    905     1304       5    1576960  1566774  ok
   6016    906    906      345547    906     1349      22    1596032  1566774  ok
```

- The same run's screenshot line says `[render] frame 6014 (343736 draws)`, and the Begin record says 342830 draws
  before frame 6014. So 906, 905 and 906 match the steps of the Vulkan counter.
- The recorded frame 6014 image is byte-identical to that screenshot.
- Frame 6016's image is pixel-identical to the suite's `race_hud` capture, and so is the recording run's own
  `race_hud` shot. Recording does not change what Vulkan draws.
- A headless recording with the null inner backend (frames 600-602) also checks ok.

Verify output (`tools/verify_task.sh 21`; see open question 5 for why not `021`), exit 0. The suite's lines were
quoted above (`frame regression: PASS, 5/5 scenes pass (7m 7s)`). The last 20 lines are the tail of the null run's
log, which run_boot echoes:
```
  0xd9 x1 first=0x0
  0xda x1 first=0x0
  0xe2 x2 first=0x0
  0xe3 x2 first=0x0
  0xe4 x2 first=0x0
  0xe5 x2 first=0x0
  0xe6 x1 first=0x0
  0xf0 x1 first=0x0
  0xf1 x1 first=0x0
  0xf2 x1 first=0x0
  0xf3 x1 first=0x0
  0xf4 x1 first=0x0
  0xf5 x1 first=0x0
  0xf6 x1 first=0x0
  0xf7 x1 first=0x0
  0xf8 x1 first=0x0
  0xf9 x1 first=0x0
[render] null backend: 2000 frames, 19615 draws submitted, 0 block transfers, 0 uploads in 106.137 s
[run_boot] exit 0 after 106.5s, 333 lines
verify 21: PASS
```

Open questions:
1. Null at > 200 fps needs a kernel change. `user_main` waits for the whole game in `sceKernelWaitThreadEnd`, which
   is a `WaitType::Host` wait. While any thread is in such a wait, `Kernel::advance_clock` (kernel.cpp:451) sleeps up
   to 1 ms of real time per clock step. Every headless run is held to about 19 frames a second (63% of real time),
   with or without a backend. A window run is paced to real time instead. Making this faster changes the kernel
   scheduler, so it needs its own brief. One option: do not sleep for host waits whose poll depends only on guest
   state, as a wait for a thread's end does. The seam itself costs nothing measurable.
2. A headless frontend route. The pad and `PURE_INPUT_SCRIPT` belong to the window shell: `ui::script` pushes SDL
   events at the `VulkanRenderer`'s window and its virtual gamepad. Without a window the game reads a neutral pad,
   so the Verify boot stays on the language screen from frame 690. With a window (`PURE_NO_RENDER` unset), null runs
   scripts but is paced. Running a route headless needs a pad source outside the window shell, which is a shell
   split.
3. `PURE_NO_RENDER=` (empty) counts as set. `portablekit::env` is `getenv`, and the Verify line depends on this.
   The brief's "(PURE_NO_RENDER unset)" would open the window and pace the run.
4. The windowed shell does not yet show a non-Vulkan backend's `PresentedImage`. With null it shows its own empty
   targets, which is the same black. For 023's Metal pictures through the window, a Cpu image could be shown through
   the shell's `upload_frame`, or 026's presenter could take the image.
5. `tools/verify_task.sh 021` runs task 017's Verify. `printf '%03d' 021` reads 021 as octal 17. My first Verify
   attempt therefore ran the three no-damage sweeps of task 017 in this worktree, on the patched build. All three
   passed (Modesto Heights, Chenghou Project and Blue Ridge, 3 laps each). I could not stop that run, because a
   process kill was refused. `tools/verify_task.sh 21` works. The fix is `$((10#$1))`; I did not change it because
   the script is outside this brief.
6. The Vulkan counter skips draws that return early in `submit`: empty index lists, a full vertex or index buffer,
   no pipeline. In such a frame the stream holds more Draw records than the counter's step, and `gerec_dump`
   reports MISMATCH. There were none in the recorded race frames.
7. For ge_replay (022), in record order:
   - Memory records come before the call that reads them.
   - A Transfer's source rows come after it, because they are what the copy read after the read-back. The replay
     must copy the rows itself.
   - Words records hold the target snapshot at each target's first draw in a frame.
   - Images are `capture_frame` BMPs of the target at the internal scale (960x544 for Vulkan, 480x272 for null).

## Review
(Fable fills)
