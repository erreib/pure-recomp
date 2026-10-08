"""PPSSPP shared with other tasks (task 050): one PPSSPPSDL at a time (its debugger port, its ini and its memory stick
are the machine's, not a worktree's), its stick holding no profile when a route starts (the routes make a new one),
and the stick left as it was found. The driver itself is tools/ppsspp/ppsspp_ctl.py (docs/ppsspp.md).
"""
import shutil, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ppsspp"))
import ppsspp_ctl as pc  # noqa: E402  (the driver, used as it is)
from purelib.port import wait_until  # noqa: E402

PROFILE_GLOB = "UCUS98612P*"            # the game's profile saves (UCUS98612P0000, ...)


def savedata():
    """PPSSPP's PSP/SAVEDATA directory (its memory stick's saves)."""
    return pc.MEMSTICK / "PSP" / "SAVEDATA"


def profiles():
    """The game's profile saves on PPSSPP's memory stick, by name ([] when none)."""
    d = savedata()
    return sorted(p.name for p in d.glob(PROFILE_GLOB)) if d.exists() else []


def wait_free(say):
    """Waits until no PPSSPPSDL runs and its stick holds no profile save (then checks PPSSPP again), saying so
    through say; False when one of the waits gave up (purelib.port.wait_until's limit)."""
    return (wait_until(pc.ppsspp_pids, f"{pc.APP_NAME} is running", say) and
            wait_until(profiles, "PPSSPP's memory stick holds a profile save", say) and
            wait_until(pc.ppsspp_pids, f"{pc.APP_NAME} is running", say))


def stick_snapshot(d=None):
    """The save folders on PPSSPP's stick (or in d) with their mtimes, to compare after a run."""
    d = Path(d) if d is not None else savedata()
    return {p.name: p.stat().st_mtime for p in d.iterdir()} if d.exists() else {}


def stick_restore(before, moved_to, say, d=None):
    """Moves every save folder a run added to PPSSPP's stick (or d) into moved_to and says so; says which folders of
    stick_snapshot's before changed or disappeared."""
    d = Path(d) if d is not None else savedata()
    after = stick_snapshot(d)
    for name in sorted(set(after) - set(before)):
        dest = Path(moved_to) / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(d / name), str(dest))
        say(f"memory stick: the run wrote {name}; moved to {dest}")
    for name in sorted(n for n in before if n in after and after[n] != before[n]):
        say(f"memory stick: warning: {name} changed during the run")
    for name in sorted(set(before) - set(after)):
        say(f"memory stick: warning: {name} disappeared during the run")
