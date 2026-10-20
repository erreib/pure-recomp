# 502: A key that marks the log when a hiccup is heard

Milestone: E8 (the rig's 100 Hz sound) | Branch: task/502-hiccup-marks from batch/m2 | Status: DONE (the rig, the
planning session, 2026-10-20; rule 1, a small change made directly)

## Goal
Task 500's step 9 is Erik's ear on a played race at the Display rate, and task 501 left it as the one test of the
concern itself: the trace lines name each second's cause (`tools/audio_hiccups.py`), but matching a hiccup heard to
them meant noting the wall-clock time by hand while racing. Erik (2026-10-20): "It would be better if I could hit a
key or something like that to indicate when I hear the stutter." After this task a traced run prints `[mark] N`
into its log, in step with the `[audio]` and `[perf]` lines, when F8 is pressed or one stick is clicked, and the
reader lists the marks among the events.

## Read first
- docs/tasks/501-audio-sink-early-arming.md, "The gate" (what the reader names, the play-session command).
- vendor/portablekit/host/ui/layer.cpp, `Layer::handle_event`: the event hook both shells install (the Vulkan
  renderer's `set_event_hook`, the Metal shell's `event_hook_`); Esc and the both-sticks menu toggle live there, a
  single stick click did nothing.
- tools/patches.sh header: `export NNNN-slug` for a new patch at the end of the series.

## Deliverable
1. Patch 0032-trace-marks: `mark()` in layer.cpp prints `[mark] N` (flushed) when `<PREFIX>_TRACE_AUDIO` or
   `<PREFIX>_PERF` is set, on an F8 key-down (not a repeat; the key is not consumed) and on a stick click whose other
   stick is up (the both-sticks toggle keeps its meaning; its first click marks too). Nothing in an untraced run.
2. `tools/audio_hiccups.py` reads `[mark] N` lines and prints each in its place among the audio seconds, with the
   host's second beside it.
3. Docs: the patch's row and section in patches/README.md, docs/controls.md (the keys outside the bindings),
   docs/windows.md (the play-session paragraph), docs/developing.md (the tool's row), CLAUDE.md (the `[mark]` tag),
   docs/status.md (the patch count, Next).

## Verify
`tools/patches.sh check && python3 tools/docs_check.py`, and in the window a scripted run with
`300:key F8`, `420:pad leftstick`, `540:key F8 2`, `660:pad rightstick` under `PURE_TRACE_AUDIO=1 PURE_PERF=log`
(four `[mark]` lines in order, the reader listing them) and once untraced (none).

## Result
Status: DONE.

Changed: patches/0032-trace-marks.patch (new; `tools/patches.sh export`, the series at 31), patches/README.md (the row
and the section), tools/audio_hiccups.py (`[mark]` lines), docs/controls.md, docs/windows.md, docs/developing.md,
CLAUDE.md, docs/status.md, this file.

What ran (the rig, 2026-10-20): `tools/build.sh profile` (layer.cpp, menu.cpp and the link, seconds). The scripted
window run with the trace (`out/501/marks.log`): `[mark] 1` to `[mark] 4` each printed on the line after its
`[script] frame N: ...` line (F8 at 300, leftstick at 420, F8 at 540, rightstick at 660); `tools/audio_hiccups.py`
lists them as `[mark] 1  host second 9  mark 1: heard here` and so on among the audio seconds. The same script
untraced (`marks-untraced.log`): four script steps run, no `[mark]` line. The race itself was not played: the marks
are the listener's, the test is Erik's (docs/windows.md, "Open on the rig").

Verify output:
```
ok: 31 patch(es) reproduce vendor/portablekit at 8b0c3fe
mark lines: 0, script steps run: 4       (the untraced run)
docs_check: 39 files, 0 findings: PASS
```

Open questions:
- Marks are a key or a stick click; a gamepad face button cannot mark, since the game uses them all in a race. The
  stick clicks are free because the PSP has none.
- The Mac's Metal shell installs the same layer hook, so F8 and the stick click mark there too; not run on the Mac.
