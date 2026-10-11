"""Running the port from a tool (task 050): the checkout and its binary, the environment of a test run, the scratch
data directory and memory stick, the one-game guard, PureNative under a pty, and a headless run.

The worktree rule: a tool runs the build and the game of the checkout it is in (ROOT, EXE, GAME: a git worktree has
its own build/ and game/), and looks in the main checkout (main_checkout) only for what a worktree never makes
itself, such as the campaign matrix of task 035.
"""
import os, shutil, subprocess, sys, time
from collections import namedtuple
from pathlib import Path

WINDOWS = os.name == "nt"
if not WINDOWS:
    import pty, select, termios
else:
    import threading
    from purelib.conpty import ConPty, strip_vt

from purelib.logs import FRAME_EXIT, exit_frame

ROOT = Path(os.path.abspath(__file__)).parents[2]
# The build directory is the preset's (CMakePresets.json): arm64 on macOS, win-x64 on Windows (task 054).
EXE = ROOT / "build" / ("win-x64" if WINDOWS else "arm64") / "bin" / ("PureNative.exe" if WINDOWS else "PureNative")
GAME = ROOT / "game"
# The shell and GE backend of a run whose pictures are read (screenshots, the sweep's end screens): headless on Metal
# on macOS; on Windows the Vulkan backend draws only through the Vulkan shell's window (headless, nothing is drawn),
# so such runs open a window there (task 055). Runs that read no pictures stay headless on both.
DRAWING = ("vulkan", "vulkan") if WINDOWS else ("headless", "metal")
# The backend of a headless run that reads no pictures: metal on macOS (the default path, it draws them anyway);
# null on Windows. PURE_GE_BACKEND=metal there falls back to the Vulkan GE backend, which under the headless shell
# draws into no window and leaves the guest's GE syncs astray: the main_menu route then writes no profile save and
# the race never loads, while the same route on the null backend writes both saves (the diagnosis of task 055's
# headless gap, 2026-10-08). The framework refusing vulkan under the headless shell is a vendor nicety for later.
BLIND = ("headless", "null") if WINDOWS else ("headless", "metal")
FRAME_EXIT_GRACE = 15.0     # seconds the runtime gets to shut down after the frame exit before it is killed
# What a new scratch data directory's settings.ini starts with: the menu hint ("Esc / L3+R3 opens the menu", drawn
# over a window for its first 12 s until the menu has been opened once) counts as seen, as in a player's settings; the
# enhancements are off, as original_pacing pins them (tasks 070, 072 and 073).
SCRATCH_SETTINGS = "ui.menu_hint_seen=1\ngame.sixty_fps=0\ngame.smooth_flashes=0\ngame.sprite_upscale=0\n"
CHECKOUT_VARS = ("PURE_ROOT", "PURE_MAIN_CHECKOUT")     # name checkouts, not switches: clean_env keeps them
# The framework's busy-time charge (Kernel::charge_busy_time: a thread that runs over 100 ms of wall time without a
# wait has up to 250 ms added to the virtual clock) makes a headless run's game state depend on the machine's load
# (task 051 saw it twice in twelve runs); with this switch set, to any value, the charge is off and a run repeats.
STEADY_CLOCK = "PURE_NO_BUSY_CLOCK"
# The enhancements a tool run has off unless its caller names them (original_pacing): E4, 30 fps modes (game.sixty_fps;
# task 072, D-017), E6, Flashes (game.smooth_flashes; task 070, D-016), and E7, Text and sprites (game.sprite_upscale;
# task 073, D-018). Named ORIGINAL_PACING before task 073, when the two it held were both the PSP's pacing.
ENHANCEMENTS_OFF = ("PURE_SIXTY_FPS", "PURE_SMOOTH_FLASHES", "PURE_SPRITE_UPSCALE")
REFUSED = "another PureNative is running"               # the guard's words (refuse, wait_game)
WAITED = 0.0                                            # seconds this process has spent in wait_until


def main_checkout():
    """The main checkout: PURE_MAIN_CHECKOUT, else the first entry of `git worktree list`, else ROOT."""
    if os.environ.get("PURE_MAIN_CHECKOUT"):
        return Path(os.environ["PURE_MAIN_CHECKOUT"])
    try:
        out = subprocess.run(["git", "-C", str(ROOT), "worktree", "list", "--porcelain"], capture_output=True,
                             text=True).stdout
        return Path(next(ln[len("worktree "):] for ln in out.splitlines() if ln.startswith("worktree ")))
    except (OSError, StopIteration):
        return ROOT


# ---------------------------------------------------------------------------------------------- the environment

def clean_env(extra=None, drop=None):
    """os.environ without every PURE_* and PSPRECOMP_* switch (CHECKOUT_VARS stay), or with drop (names, `PREFIX*`
    for a prefix) without only those; then extra on top."""
    def dropped(k):
        if drop is None:
            return k.startswith(("PURE_", "PSPRECOMP_")) and k not in CHECKOUT_VARS
        return any(k.startswith(d[:-1]) if d.endswith("*") else k == d for d in drop)
    env = {k: v for k, v in os.environ.items() if not dropped(k)}
    env.update(extra or {})
    return env


def scratch_data_dir(env, path):
    """Sets PURE_DATA_DIR in env to path (relative to the checkout), made on first use with SCRATCH_SETTINGS and kept
    between runs, unless env already names a data directory; returns the directory the run uses (task 034)."""
    if env.get("PURE_DATA_DIR"):
        return env["PURE_DATA_DIR"]
    path = os.path.join(ROOT, path)
    os.makedirs(path, exist_ok=True)
    settings = os.path.join(path, "settings.ini")
    if not os.path.exists(settings):
        with open(settings, "w") as f:
            f.write(SCRATCH_SETTINGS)
    env["PURE_DATA_DIR"] = path
    return path


def silence(env, sound=False, window=True):
    """PURE_NO_AUDIO=1 unless sound is asked for or env decides (task 034): env sets PURE_NO_AUDIO, or PURE_AUDIO_WAV
    with a window. No audio device only: the game's sceAudio calls still run on the virtual clock and PURE_AUDIO_WAV
    still captures them. Also original_pacing(env), so every run made through here has the PSP's pacing."""
    if not sound and "PURE_NO_AUDIO" not in env and not (window and "PURE_AUDIO_WAV" in env):
        env["PURE_NO_AUDIO"] = "1"
    original_pacing(env)


def steady_clock(env):
    """PURE_NO_BUSY_CLOCK=1 for a headless test run (the busy-time charge off, so the run does not depend on the
    machine's load) unless env names it already; windowed and sound-on runs, a player's, are not given it. Also
    original_pacing(env), as silence() does."""
    env.setdefault(STEADY_CLOCK, "1")
    original_pacing(env)


def original_pacing(env):
    """The enhancements off: PURE_SIXTY_FPS=0, PURE_SMOOTH_FLASHES=0 and PURE_SPRITE_UPSCALE=0, each unless env names it
    (ENHANCEMENTS_OFF). Time Trial, Free Play and Zone keep the PSP's two vblanks a frame (task 072, D-017), so do the
    full-screen flashes (task 070, D-016), and the Metal backend draws the menus' and the HUD's bitmaps as the PSP's
    texels (task 073, D-018), so every tool's run measures the game as the PSP paces and draws it and the suites'
    scenes, the HUD check and the sweep stay where they were measured. The name is the first two's. Every tool run
    calls it, through silence() and steady_clock() (run_boot, campaign_sweep and what goes through them);
    tools/framerate_check.sh, tools/flash_check.sh and tools/sprite_check.sh are the checks that name them."""
    for name in ENHANCEMENTS_OFF:
        env.setdefault(name, "0")


def fresh_stick(game_dir):
    """Makes game_dir a game directory on an empty memory stick (EBOOT.ELF linked to game/'s, disc.iso to the image
    game/disc.iso names, ms0/PSP/SAVEDATA emptied) and returns it; FileNotFoundError naming a file game/ lacks."""
    g = Path(game_dir)
    g.mkdir(parents=True, exist_ok=True)
    for name in ("EBOOT.ELF", "disc.iso"):
        target = Path(os.path.realpath(GAME / name))
        if not target.exists():
            raise FileNotFoundError(f"{GAME / name} is missing (tools/setup_game.sh)")
        link = g / name
        if link.is_symlink() or link.exists():
            link.unlink()
        if WINDOWS:     # no symlinks without Developer Mode; a hard link on the same volume does (task 054)
            os.link(target, link)
        else:
            link.symlink_to(target)
    shutil.rmtree(g / "ms0", ignore_errors=True)
    (g / "ms0" / "PSP" / "SAVEDATA").mkdir(parents=True)
    return g


# ------------------------------------------------------------------------------------------- one game at a time

def other_games():
    """The PureNative processes running now (`pgrep -f build/.*/bin/PureNative`, kept when the executable itself is
    PureNative, not a command line that mentions it; on Windows, tasklist by image name), as (pid, command) pairs
    (task 034: one game at a time)."""
    if WINDOWS:
        try:
            out = subprocess.run(["tasklist", "/FO", "CSV", "/NH", "/FI", "IMAGENAME eq PureNative.exe"],
                                 capture_output=True, text=True).stdout
        except OSError:
            return []
        games = []
        for line in out.splitlines():
            parts = [p.strip('"') for p in line.split('","')]
            if len(parts) >= 2 and parts[0].strip('"') == "PureNative.exe":
                games.append((int(parts[1]), "PureNative.exe"))
        return games
    try:
        pids = subprocess.run(["pgrep", "-f", "build/.*/bin/PureNative"], capture_output=True, text=True).stdout.split()
    except OSError:
        return []
    games = []
    for pid in pids:
        def ps(field):
            return subprocess.run(["ps", "-o", f"{field}=", "-p", pid], capture_output=True, text=True).stdout.strip()
        if os.path.basename(ps("comm")) == "PureNative":
            games.append((int(pid), ps("command")))
    return games


def refuse(tool, allow_parallel=False):
    """The guard of a tool that will not start beside another game: prints `TOOL: another PureNative is running; ...`
    and each game, and returns True, while one runs; never with allow_parallel (--allow-parallel)."""
    others = [] if allow_parallel else other_games()
    if others:
        print(f"{tool}: {REFUSED}; one game at a time (--allow-parallel starts anyway):\n"
              + "\n".join(f"  pid {pid}: {command}" for pid, command in others), flush=True)
    return bool(others)


def wait_until(busy, what, say, limit=3600.0):
    """Waits while busy() names something (another game, another PPSSPP, a profile on PPSSPP's stick), saying so
    through say: one at a time, and a process this tool did not start is never touched. False after limit s."""
    global WAITED
    t0, said = time.time(), False
    while True:
        b = busy()
        if not b:
            if said:
                say(f"{what}: free after {time.time() - t0:.0f} s")
                WAITED += time.time() - t0
            return True
        if not said:
            say(f"waiting: {what} ({b})")
            said = True
        if time.time() - t0 > limit:
            say(f"gave up waiting after {limit:.0f} s: {what} ({b})")
            return False
        time.sleep(10)


def wait_game(say):
    """Waits while another PureNative runs (the guard of a tool that waits rather than refuses, as the scorecard)."""
    return wait_until(other_games, REFUSED, say)


def waited():
    """The seconds this process has spent waiting in wait_until (for another task's game or PPSSPP)."""
    return WAITED


# --------------------------------------------------------------------------------------------- running the game

class PtyRun:
    """PureNative under a pty, so its stdout is line-buffered and nothing is lost when it is killed. The output is
    folded into the log as it arrives (a repeated line becomes `    ... (xN)`; the log stops at max_lines while the
    game runs on); the game is killed at the deadline, or FRAME_EXIT_GRACE s after `[pure] exit at frame`. The pty's
    slave end stays open in the parent until the output is drained: macOS discards unread pty output once the last
    slave descriptor closes. Used by tools/run_boot.py and tools/campaign_sweep.py (which steers from the lines)."""

    def __init__(self, env, log_path, seconds, max_lines, line_buffered=False):
        """Starts the game with env, writing the folded log to log_path; seconds is the wall-clock deadline."""
        os.makedirs(os.path.dirname(os.path.abspath(log_path)) or ".", exist_ok=True)
        self.seconds = seconds
        self.start = time.time()
        self.deadline = self.start + seconds
        if WINDOWS:
            # No pty on Windows: a pseudoconsole (ConPTY, purelib/conpty.py; task 055) and a reader thread. Its C
            # runtime sees a console, so the game's stdout is not block-buffered: through a plain pipe (task 054)
            # its `[pure] ship` lines reached the sweep about 1 s (56 flips) late in bursts, and the follower lost
            # the road. The console's VT sequences are removed line by line in _take.
            self.master = self.slave = None
            self.p = ConPty([str(EXE)], ROOT, env)
            self._lock = threading.Condition()
            self._pending = []              # byte chunks the reader thread has taken off the pipe
            self._eof = False
            self._reader = threading.Thread(target=self._read_pipe, daemon=True)
            self._reader.start()
        else:
            self.master, self.slave = pty.openpty()
            attrs = termios.tcgetattr(self.slave)
            attrs[1] &= ~termios.OPOST          # no "\r\n" translation on output
            termios.tcsetattr(self.slave, termios.TCSANOW, attrs)
            self.p = subprocess.Popen([str(EXE)], cwd=ROOT, env=env, stdin=subprocess.DEVNULL, stdout=self.slave,
                                      stderr=self.slave)
        # newline="\n": the bash tools grep the logs with `$` anchors, which a Windows "\r\n" would defeat (task 055).
        self.log = open(log_path, "w", buffering=1 if line_buffered else -1, newline="\n")
        self.buf = b""
        self.last, self.repeat, self.written, self.max_lines = None, 0, 0, max_lines
        self.tail = []                      # the last 25 lines given to the log, folded and closing lines too
        self.frame_exit = self.timed_out = self.killed = False

    def emit(self, line, always=False):
        """Writes a line to the log; up to max_lines (then one `... log capped` line), or past the cap with always."""
        if always:                          # a tool's own closing lines are written past the cap too
            self.log.write(line + "\n")
        elif self.written < max(self.max_lines, 0):
            self.log.write(line + "\n")
            self.written += 1
            if self.written == self.max_lines:
                self.log.write(f"... log capped at {self.max_lines} lines\n")
        self.tail.append(line)
        del self.tail[:-25]

    def _flush_repeat(self):
        if self.repeat > 1:
            self.emit(f"    ... (x{self.repeat})")
        self.repeat = 0

    def _take(self, raw, out):
        if WINDOWS:
            raw = strip_vt(raw).replace(b"\r", b"")
        line = raw.decode("utf-8", "replace").rstrip("\r")
        if not self.frame_exit and line.startswith(FRAME_EXIT):
            self.frame_exit = True
            self.deadline = min(self.deadline, time.time() + FRAME_EXIT_GRACE)
        out.append(line)
        if line == self.last:
            self.repeat += 1
            return
        self._flush_repeat()
        self.last, self.repeat = line, 1
        self.emit(line)

    def _read_pipe(self):
        """Windows only: moves the game's output off the pipe as it comes, so the game never blocks on a full pipe."""
        while True:
            try:
                chunk = self.p.read(65536)
            except (OSError, ValueError):
                chunk = b""
            with self._lock:
                if chunk:
                    self._pending.append(chunk)
                else:
                    self._eof = True
                self._lock.notify_all()
            if not chunk:
                return

    def _chunk(self, timeout, out):
        """Reads what the pty (or, on Windows, the reader thread) holds within timeout into out (whole lines);
        False when nothing arrived."""
        if WINDOWS:
            with self._lock:
                if not self._pending and not self._eof:
                    self._lock.wait(timeout)
                if not self._pending:
                    return False
                chunk = b"".join(self._pending)
                self._pending = []
        else:
            ready, _, _ = select.select([self.master], [], [], timeout)
            if not ready:
                return False
            try:
                chunk = os.read(self.master, 65536)
            except OSError:
                return False
            if not chunk:
                return False
        self.buf += chunk
        *lines, self.buf = self.buf.split(b"\n")
        for raw in lines:
            self._take(raw, out)
        return True

    def read(self, timeout):
        """The lines (unfolded) that arrive within timeout; kills the game once the deadline has passed."""
        if self.p.poll() is None and time.time() > self.deadline:
            self.timed_out = not self.frame_exit
            self.kill()
        out = []
        self._chunk(timeout, out)
        return out

    def alive(self):
        """True while the game runs."""
        return self.p.poll() is None

    def kill(self):
        """Kills the game (a deadline, or an error in the tool: never leave the game running)."""
        self.killed = True
        self.p.kill()

    def drain(self):
        """Waits for the game to end (killed after 10 s), reads what the pty still holds (5 s at most), closes the pty
        and folds the last repeat; returns the lines read."""
        try:
            self.p.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.p.kill()
            self.p.wait()
        out = []
        end = time.time() + 5.0
        while self._chunk(0.05, out) and time.time() < end:
            pass
        if WINDOWS:
            self._reader.join(timeout=5)
            self._chunk(0.05, out)
        else:
            os.close(self.slave)
            os.close(self.master)
        if self.buf:
            self._take(self.buf, out)
            self.buf = b""
        self._flush_repeat()
        return out

    @property
    def returncode(self):
        """The game's exit status (negative for a signal), None while it runs."""
        return self.p.returncode

    def code(self, signals=False):
        """0 after the frame exit, 124 at the deadline, else the game's status (with signals, 128 + the signal)."""
        if self.frame_exit:
            return 0
        if self.timed_out:
            return 124
        rc = self.p.returncode
        return 128 - rc if signals and rc < 0 else rc

    def close(self, tag, signals=False):
        """Writes `[TAG] exit CODE after S s, N lines` past the cap, closes the log and returns the code."""
        code = self.code(signals)
        self.emit(f"[{tag}] exit {code} after {time.time() - self.start:.1f}s, {self.written} lines", True)
        self.log.close()
        return code


Run = namedtuple("Run", "code frame reached log")   # headless_run: run_boot's exit code, the exit frame, the log


def headless_run(log, script, frames, shell="headless", backend=BLIND[1], paced_from=None, env=None, shots=None,
                 game=None, data_dir=None, seconds=None, max_lines=None, stdout=None):
    """One run through tools/run_boot.py in clean_env(): the input script, to flip frames, with the shell and the GE
    backend, PURE_PACED_FROM, env as --env, shots (--shots), game (PURE_GAME_DIR), data_dir (--data-dir), run_boot's
    output to the file stdout; a Run with the exit code, the exit frame (None without one), frames reached, the log."""
    cmd = [sys.executable, str(ROOT / "tools" / "run_boot.py"), "--shell", shell, "--backend", backend,
           "--script", str(script), "--frames", str(frames),
           "--seconds", str(seconds if seconds is not None else max(120, frames // 20))]
    if max_lines is not None:
        cmd += ["--max-lines", str(max_lines)]
    if data_dir is not None:
        cmd += ["--data-dir", str(data_dir)]
    if game is not None:
        cmd += ["--env", f"PURE_GAME_DIR={game}"]
    if shots is not None:
        cmd += ["--shots", str(shots)]
    if paced_from is not None:
        cmd += ["--env", f"PURE_PACED_FROM={paced_from}"]
    for k, v in (env or {}).items():
        cmd += ["--env", f"{k}={v}"]
    cmd.append(str(log))
    code = run_tool(cmd, stdout, clean_env())
    frame = exit_frame(log)
    return Run(code, frame, frame == frames, Path(log))


def run_tool(cmd, out=None, env=None):
    """Runs a command (another tool) from the checkout's root, its stdout and stderr to the file out (else this
    process's), with env (else this process's); returns its exit code."""
    if WINDOWS and str(cmd[0]).endswith(".sh"):
        # No shebangs on Windows: the bash tools go through Git Bash's bash, found on PATH (CreateProcess would find
        # System32's bash.exe, WSL's, first).
        cmd = [shutil.which("bash") or "bash", str(cmd[0])] + list(cmd[1:])
    if out is None:
        return subprocess.run(cmd, cwd=ROOT, env=env).returncode
    with open(out, "w") as f:
        return subprocess.run(cmd, cwd=ROOT, env=env, stdout=f, stderr=subprocess.STDOUT).returncode
