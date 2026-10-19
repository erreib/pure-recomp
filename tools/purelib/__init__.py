"""The shared parts of the test tools (task 050): one copy of what tools/run_boot.py, tools/scorecard.py,
tools/campaign_sweep.py, tools/fidelity_audit.py, tools/vfpu_probe.py, tools/pp_lines.py and tools/ai_seed_check.sh
each used to carry.

  purelib.port     the checkout and the binary, the environment of a test run, the scratch data directory and memory
                   stick, the one-game guard, PureNative under a pty, a headless run through tools/run_boot.py
  purelib.logs     the readers of a run's log: the [pure] ship, grid and exit lines, the [metal] exit lines, the
                   [hle-stub] lines and the start-up list, the PURE_AUDIO_WAV files; since task 094 also the checks'
                   readers (the sweep's result line and a cell's trace, the flip times, E8's display-rate lines, the
                   [perf], [stalls], [slow-frame] and [audio] lines), the window guard of a window run, and the
                   fidelity audit's scan of a sweep log; `python3 tools/purelib/logs.py --selftest`
  purelib.ppsspp   PPSSPP shared with other tasks: one instance at a time, its memory stick free of a profile and left
                   as it was found
  purelib.dlc      (task 077) the download packs: the twelve US pack folders and their titles, the checks
                   tools/dlc_install.sh makes on a folder, the app's data directory

A tool puts tools/ on sys.path (as every tool does for tools/png.py) and imports `from purelib import port, logs`.
Python 3 standard library only. docs/verification.md, "The shared runner".
"""
