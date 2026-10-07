"""The readers of a port run's log (task 050): the line formats the tools match, in one place.

The profile's probes (src/profile/pure_profile.cpp) print `[pure] ship` lines (PURE_WATCH_SHIP: the player's race
record each flip, and `player object ... index K` when a race's ship appears), `[pure] grid` lines (PURE_WATCH_GRID:
every race record when it changes) and `[pure] exit at frame N` (PURE_EXIT_AT_FRAME). The framework prints the
start-up list of unimplemented imports (PURE_LIST_STUBS), a stub's first call as `[hle-stub] NAME ... ra=0x...`, and
at exit the Metal backend's counts and the GE commands it ignored. PURE_AUDIO_WAV=FILE writes the mix to FILE and
each sceAudio channel N to FILE.chN.wav (src/hle/audio_capture.cpp).
"""
import re

FRAME_EXIT = "[pure] exit at frame"     # the profile's line when PURE_EXIT_AT_FRAME stops the runtime
FRAME_EXIT_RE = re.compile(r"\[pure\] exit at frame (\d+)")
FRAME_RE = re.compile(r"\[pure\] frame (\d+)")                       # PURE_FRAME_LOG's flip counter

# A ship line, every field: frame, clock, x, y, z, vx, vy, vz, kmh, dist, lap, shield (tools/campaign_sweep.py's).
SHIP_RE = re.compile(r"\[pure\] ship frame (\d+) t=\d+ clock=(\S+) pos=(\S+),(\S+),(\S+) vel=(\S+),(\S+),(\S+) "
                     r"kmh=(\S+) dist=(\S+) lap=(\d+)(?: shield=(\S+))?")
# A ship line with its virtual time: frame, t (us), clock, kmh, dist, lap (tools/fidelity_audit.py's; match()).
SHIP_T_RE = re.compile(r"^\[pure\] ship frame (\d+) t=(\d+) clock=(\S+) pos=\S+ vel=\S+ kmh=(\S+) dist=(\S+) "
                       r"lap=(\d+)")
# A race's ship appears: frame, object, the player's index in the race records.
PLAYER_RE = re.compile(r"\[pure\] ship frame (\d+) player object (\S+) index (\d+)")
# A race record: frame, k, clock, x, y, z, vx, vy, vz, dist, lap.
GRID_RE = re.compile(r"\[pure\] grid frame (\d+) k=(\d+) clock=(\S+) pos=(\S+),(\S+),(\S+) vel=(\S+),(\S+),(\S+) "
                     r"dist=(\S+) lap=(\d+)")
RACE_OVER = 0x10000     # lap field bit 16: that ship has finished (docs/tracks.md)

STUB_RE = re.compile(r"\[hle-stub\] (\S+)")                          # a stub's first call: its label
RA_RE = re.compile(r"\bra=(0x[0-9A-Fa-f]+)")
UNIMPL_RE = re.compile(r"Unimplemented imports: (\d+) of (\d+)")     # the start-up list's header (PURE_LIST_STUBS)
HALT_RE = re.compile(r"\[hle-stub\]|unsupported|Runtime stopped")    # a line that may end a run early

# The Metal backend's exit line. Tasks 036 and 037 inserted "texture-mapped draws" and "mipmapped draws (... mip
# levels decoded after the first)" after the framebuffer textures; both are optional so older logs still parse.
METAL_EXIT_RE = re.compile(r"^\[metal\] (\d+) frames, (\d+) draws, (\d+) passes, (\d+) textures decoded, (\d+) "
                           r"framebuffer textures, (?:\d+ texture-mapped draws, )?(?:\d+ mipmapped draws \([^)]*\), )?"
                           r"(\d+) target copies, (\d+) uploads, (\d+) targets, (\d+) GPU waits "
                           r"\(([\d.]+) ms\) in ([\d.]+) s")
METAL_PIPE_RE = re.compile(r"^\[metal\] pipelines: (\d+) render pipelines used, (\d+) made by a draw \((\d+) of them "
                           r"waited for the pre-warm, (\d+) not in the list\).*?; (\d+) depth-stencil states, "
                           r"(\d+) made")
METAL_FPS_RE = re.compile(r"^\[metal\] frame (\d+), \d+ draws \(\d+ in the last \d+ frames, ([\d.]+) fps\)")
GE_COUNT_RE = re.compile(r"^GE commands ignored: (\d+) distinct")    # the framework's exit list, then one line each:
GE_IGNORED_RE = re.compile(r"^  0x([0-9a-f]+) x(\d+) first=0x([0-9a-f]+)$")
UNDERRUN_RE = re.compile(r"\[pure\] audio capture: channel (\d+) underrun")


def exit_frame(path):
    """The N of the log's `[pure] exit at frame N` line (the run stopped at its PURE_EXIT_AT_FRAME), or None."""
    try:
        with open(path, errors="replace") as f:
            m = FRAME_EXIT_RE.search(f.read())
    except OSError:
        return None
    return int(m[1]) if m else None


def grid_samples(path):
    """The first race's grid records of a PURE_WATCH_GRID log: ([(frame, k, clock, x, y, z, vx, vy, vz, dist, lap)],
    the player's index), before GO and ships whose race is over left out."""
    rows, player, races = [], 7, 0
    with open(path, errors="replace") as f:
        for line in f:
            m = PLAYER_RE.search(line)
            if m:
                races += 1
                if races > 1:
                    break
                player = int(m[3])
                continue
            m = GRID_RE.search(line)
            if not m or races == 0:
                continue
            frame, k, lap = int(m[1]), int(m[2]), int(m[11])
            vals = [float(v) for v in m.groups()[2:10]]
            if vals[0] <= 0.0 or lap & RACE_OVER:
                continue                # before GO, or that ship's race is over
            rows.append((frame, k, *vals, lap))
    return rows, player


def metal_exit(line):
    """The Metal backend's exit counts in a line ({frames, draws, textures, waits, wait_ms, seconds}), or None."""
    m = METAL_EXIT_RE.match(line)
    return m and dict(frames=int(m[1]), draws=int(m[2]), textures=int(m[4]), waits=int(m[9]), wait_ms=float(m[10]),
                      seconds=float(m[11]))


def metal_pipelines(line):
    """The Metal backend's exit line on pipelines ({pipelines, pipelines_made, pipelines_unlisted, depth_states,
    depth_made}), or None."""
    m = METAL_PIPE_RE.match(line)
    return m and dict(pipelines=int(m[1]), pipelines_made=int(m[2]), pipelines_unlisted=int(m[4]),
                      depth_states=int(m[5]), depth_made=int(m[6]))


def ge_ignored(path):
    """The framework's exit list of the GE commands it ignored, {opcode: count}, or None when the log has none."""
    out, inside = None, False
    with open(path, errors="replace") as f:
        for line in f:
            if GE_COUNT_RE.match(line):
                out, inside = {}, True
                continue
            if inside:
                m = GE_IGNORED_RE.match(line.rstrip("\n"))
                if m:
                    out[int(m[1], 16)] = int(m[2])
                    continue
                inside = False
    return out


def unimplemented(text):
    """The names in the start-up list of unimplemented imports (PURE_LIST_STUBS) in a log's text, [] without one."""
    m = re.search(r"^Unimplemented imports: \d+ of \d+\n((?:  .*\n)+)", text, re.M)
    return [ln.strip() for ln in m[1].splitlines() if ln.startswith("    ")] if m else []


def wav_channel(wav, n):
    """The file PURE_AUDIO_WAV=wav writes sceAudio channel n to (1 the sceSas mix, 2 the music, 3 movie audio)."""
    return f"{wav}.ch{n}.wav"


def wav_files(wav):
    """Every file a PURE_AUDIO_WAV=wav capture may write: the mix, then channels 1 to 4."""
    return [str(wav)] + [wav_channel(wav, n) for n in range(1, 5)]
