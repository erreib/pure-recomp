#!/opt/homebrew/bin/python3
"""Scripted driver for PPSSPP (SDL build, macOS) through its WebSocket debugger.

Boots a PSP image in PPSSPPSDL, feeds a frame-indexed button script, saves display screenshots and GE dumps at
given frames, optionally saves a state, and quits. Python 3 standard library only. Full notes: docs/ppsspp.md.

Usage (paths are relative to the current directory):
  ppsspp_ctl.py run [--pad SCRIPT | --pad-file FILE...] [--shot F:PNG]... [--gedump F:PPDMP]...
                    [--shots-every N [--shots-dir DIR]] [--until F] [--log FILE] [--savestate FILE] [--report JSON]
  ppsspp_ctl.py launch [--log FILE] [--run]   boot the ISO with the debugger on and leave PPSSPP running
  ppsspp_ctl.py status                        print game.status, cpu.status and the current frame
  ppsspp_ctl.py shot PNG                      capture the next frame of the running game
  ppsspp_ctl.py gedump PPDMP                  GE-record the next frame of the running game (PNG of it next to it)
  ppsspp_ctl.py quit                          quit PPSSPP cleanly (SIGTERM; it saves its config)
  ppsspp_ctl.py ini apply|restore|show        driver settings in ppsspp.ini; restore copies ppsspp.ini.orig back

Pad script: comma or newline separated `FRAME:BUTTONS` items; `#` starts a comment. From FRAME on the held set is
exactly BUTTONS (`+` separated: CROSS CIRCLE SQUARE TRIANGLE UP DOWN LEFT RIGHT START SELECT L R); an empty set
releases everything. `A=x/y` in the set holds the left stick at x,y in -1..1 (centred otherwise).
Example: `120:CROSS,130:,300:START,310:` holds CROSS for frames 120-129 and START for frames 300-309.

A frame number is a vblank count since boot. Frame N is the interval during which PPSSPP's vblank counter equals N;
it starts at emulated time V(N) = 15951.8 us + (N-1) * 16683.3 us. Input is fed through PPSSPP's replay engine with
emulated-time stamps, so it lands on exact vblank samples whatever the host speed. A capture at frame N is the
first frame the game starts drawing after its first sceDisplaySetFrameBuf call at or after V(N): the GE dump holds
that frame's command stream and the PNG holds its finished pixels, read from VRAM when the game flips it.
"""
import argparse, base64, ctypes, hashlib, json, math, os, queue, re, shutil, signal, socket, struct, subprocess
import sys, threading, time, zlib
from pathlib import Path

VERSION = "1.0"
REPO = Path(__file__).resolve().parents[2]
APP = Path("/Applications/PPSSPPSDL.app/Contents/MacOS/PPSSPPSDL")
MEMSTICK = Path.home() / ".config/ppsspp"          # SDL build on macOS: $HOME/.config/ppsspp (checked 2026-10-05)
SYSDIR = MEMSTICK / "PSP/SYSTEM"
INI = SYSDIR / "ppsspp.ini"
CONTROLS = SYSDIR / "controls.ini"
DUMPDIR = SYSDIR / "DUMP"                          # gpu.record.dump writes <DISCID>_NNNN.ppdmp here
STATEDIR = MEMSTICK / "PSP/PPSSPP_STATE"
DEFAULT_ISO = REPO / "disc.iso"
DEFAULT_PORT = 45333
OUTDIR = REPO / "out/ppsspp"
SETFB_STUB = "zz_sceDisplaySetFrameBuf"            # PPSSPP labels every import stub zz_<function>

# Display timing (PPSSPP Core/HLE/sceDisplay.cpp): a frame is 1001/60 ms; vblank 1 starts 0.7315 ms before the end
# of the first frame. Measured on Wipeout Pure: the main thread returns from sceDisplayWaitVblankStartCB 5 us
# after V(N), for N from 296 to 2996, so the model has no drift.
FRAME_US = 1001000.0 / 60.0
VBLANK1_US = FRAME_US - 731.5

BUTTONS = {
    "SELECT": 0x0001, "START": 0x0008, "UP": 0x0010, "RIGHT": 0x0020, "DOWN": 0x0040, "LEFT": 0x0080,
    "L": 0x0100, "LTRIGGER": 0x0100, "R": 0x0200, "RTRIGGER": 0x0200, "TRIANGLE": 0x1000, "CIRCLE": 0x2000,
    "CROSS": 0x4000, "SQUARE": 0x8000, "HOME": 0x10000, "NOTE": 0x800000, "SCREEN": 0x400000,
    "VOLUP": 0x100000, "VOLDOWN": 0x200000,
}

# Settings the driver needs. Everything else in ppsspp.ini is left alone.
DRIVER_SETTINGS = {
    "General": {
        "FirstRun": "False",
        "AutoRun": "False",                  # boot into a CPU break so the script starts at emulated time 0
        "RemoteDebuggerOnStartup": "True",   # start the web server with the debugger on
        "RemoteISOPort": None,               # the debugger port (--port)
        "CheckForNewVersion": "False",
        "PauseOnLostFocus": "False",
        "PauseWhenMinimized": "False",
        "Enable Logging": "True",
        "RewindSnapshotInterval": "0",
        "AutoLoadSaveState": "0",
        "EnableCheats": "False",
        "WindowWidth": "960",
        "WindowHeight": "544",
    },
    "Graphics": {
        "GraphicsBackend": "3 (VULKAN)",
        "SoftwareRenderer": None,            # True for --renderer software (screenshots need it), else False
        "InternalResolution": "1",
        "FrameSkip": "0",
        "AutoFrameSkip": "False",
        "FullScreen": "False",
    },
    "SystemParam": {
        "GameLanguage": "1",                 # English
        "ButtonPreference": "1",             # CROSS confirms (US)
    },
}
MUTE_SETTINGS = {"Sound": {"GameVolume": "0"}}
# --log: the categories named in the task at Debug (sceKernel at Info: Debug logs every context switch, 20k lines/s).
HLE_LOG_LEVELS = {"SCEUTIL": 5, "SCEDISP": 5, "MPEG": 5, "SCEIO": 5, "SCEKERNEL": 4, "ME": 4, "ATRAC": 4,
                  "HLE": 4, "SCEMODULE": 4, "LOADER": 4, "BOOT": 4, "SYSTEM": 4, "SCEGE": 4, "SCEAUDIO": 4,
                  "SCESAS": 4, "SCECTRL": 4, "SCERTC": 4}
SAVESTATE_KEY = "1-132"                      # keyboard F2, mapped to "Save State" in controls.ini for --savestate
MAC_KEYCODE_F2 = 120


def log(msg):
    print(f"[ppsspp_ctl] {msg}", flush=True)


def die(msg):
    print(f"[ppsspp_ctl] error: {msg}", file=sys.stderr, flush=True)
    sys.exit(1)


# ---------------------------------------------------------------- frames <-> emulated time

def vblank_us(n):
    """Emulated microseconds at which vblank n (1-based) starts."""
    return VBLANK1_US + (n - 1) * FRAME_US


def input_time_us(frame):
    """Replay timestamp for a pad change at `frame`: half a frame before vblank `frame`, so that sample sees it."""
    return 0 if frame <= 0 else int(vblank_us(frame) - FRAME_US / 2)


def frame_at_us(us):
    """Vblank count at emulated time `us`; the fraction is the position inside the frame."""
    return (us - VBLANK1_US) / FRAME_US + 1


# ---------------------------------------------------------------- pad scripts

def parse_pad_script(text):
    """Return a sorted list of (frame, buttons, (x, y)). Later items for the same frame win."""
    items = {}
    body = "\n".join(ln.split("#", 1)[0] for ln in text.splitlines())
    for tok in re.split(r"[,\n]", body):
        tok = tok.strip()
        if not tok:
            continue
        frame_s, sep, rest = tok.partition(":")
        if not sep or not frame_s.strip().isdigit():
            die(f"bad pad item {tok!r} (want FRAME:BUTTONS)")
        mask, stick = 0, (0.0, 0.0)
        for name in re.split(r"[+|]", rest):
            name = name.strip().upper()
            if not name:
                continue
            m = re.fullmatch(r"A=(-?[0-9.]+)/(-?[0-9.]+)", name)
            if m:
                stick = (max(-1.0, min(1.0, float(m.group(1)))), max(-1.0, min(1.0, float(m.group(2)))))
            elif name in BUTTONS:
                mask |= BUTTONS[name]
            else:
                die(f"unknown button {name!r} in {tok!r}")
        items[int(frame_s)] = (mask, stick)
    return [(f, m, s) for f, (m, s) in sorted(items.items())]


def stick_bytes(x, y):
    # Same scaling as PPSSPP __CtrlSetAnalogXY: u8 = ceil(v*127.5+127.5), y inverted.
    clamp = lambda v: max(0, min(255, v))
    return clamp(math.ceil(x * 127.5 + 127.5)), clamp(math.ceil(-y * 127.5 + 127.5))


def build_replay_blob(states):
    """PPSSPP replay items (Core/Replay.cpp, packed): u8 action, u64 emulated-time stamp in us, 8-byte payload.
    Action 0 = buttons (u32 mask), 1 = analog (u8 [stick][x,y])."""
    out = bytearray()
    # While a replay executes it overrides the sticks with its own state, which starts at (0,0) = up-left.
    out += struct.pack("<BQ4B4x", 1, 0, 128, 128, 128, 128)
    out += struct.pack("<BQI4x", 0, 0, 0)
    last_stick = (128, 128)
    for frame, mask, (x, y) in states:
        t = input_time_us(frame)
        sb = stick_bytes(x, y) if (x, y) != (0.0, 0.0) else (128, 128)
        if sb != last_stick:
            out += struct.pack("<BQ4B4x", 1, t, sb[0], sb[1], 128, 128)
            last_stick = sb
        out += struct.pack("<BQI4x", 0, t, mask)
    return bytes(out)


# ---------------------------------------------------------------- ini handling

class Ini:
    """Minimal editor for PPSSPP's `Key = Value` ini files that keeps order, comments and the UTF-8 BOM."""

    def __init__(self, path):
        self.path = Path(path)
        raw = self.path.read_bytes()
        self.bom = raw.startswith(b"\xef\xbb\xbf")
        self.lines = raw.decode("utf-8-sig").splitlines()

    def _section_range(self, section):
        start = None
        for i, ln in enumerate(self.lines):
            s = ln.strip()
            if s.startswith("[") and s.endswith("]"):
                if start is not None:
                    return start, i
                if s[1:-1] == section:
                    start = i + 1
        return (start, len(self.lines)) if start is not None else (None, None)

    def get(self, section, key):
        a, b = self._section_range(section)
        if a is None:
            return None
        for ln in self.lines[a:b]:
            k, sep, v = ln.partition("=")
            if sep and k.strip() == key:
                return v.strip()
        return None

    def set(self, section, key, value):
        a, b = self._section_range(section)
        if a is None:
            self.lines += ["", f"[{section}]", f"{key} = {value}"]
            return
        for i in range(a, b):
            k, sep, _ = self.lines[i].partition("=")
            if sep and k.strip() == key:
                self.lines[i] = f"{key} = {value}"
                return
        j = b
        while j > a and not self.lines[j - 1].strip():
            j -= 1
        self.lines.insert(j, f"{key} = {value}")

    def save(self):
        data = "\n".join(self.lines) + "\n"
        self.path.write_bytes((b"\xef\xbb\xbf" if self.bom else b"") + data.encode("utf-8"))


def ensure_config_exists():
    if INI.exists():
        return
    log(f"{INI} missing; starting PPSSPP once without a game to create it")
    p = subprocess.Popen([str(APP), "--windowed"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(100):
        time.sleep(0.2)
        if SYSDIR.exists():
            break
    time.sleep(2)
    stop_process(p.pid, p)
    if not INI.exists():
        die("PPSSPP did not create its ini")


def backup_original():
    """ppsspp.ini.orig / controls.ini.orig = PPSSPP's files before the driver first touched them. Never overwritten."""
    for f in (INI, CONTROLS):
        orig = f.with_name(f.name + ".orig")
        if f.exists() and not orig.exists():
            shutil.copy2(f, orig)
            log(f"backed up {f.name} -> {orig}")


def apply_driver_settings(port, renderer="software", hle_log=False, mute=True, savestate_key=False):
    ensure_config_exists()
    backup_original()
    ini = Ini(INI)
    changed = []
    for group in [DRIVER_SETTINGS] + ([MUTE_SETTINGS] if mute else []):
        for section, kv in group.items():
            for k, v in kv.items():
                if k == "RemoteISOPort":
                    v = str(port)
                elif k == "SoftwareRenderer":
                    v = "True" if renderer == "software" else "False"
                if ini.get(section, k) != v:
                    changed.append(f"[{section}] {k} = {v}")
                ini.set(section, k, v)
    if hle_log:
        for cat, lvl in HLE_LOG_LEVELS.items():
            ini.set("Log", f"{cat}Enabled", "True")
            ini.set("Log", f"{cat}Level", str(lvl))
        changed.append("[Log] HLE categories raised (see HLE_LOG_LEVELS)")
    ini.save()
    if savestate_key and CONTROLS.exists():
        c = Ini(CONTROLS)
        if c.get("ControlMapping", "Save State") != SAVESTATE_KEY:
            c.set("ControlMapping", "Save State", SAVESTATE_KEY)
            c.save()
            changed.append(f"controls.ini [ControlMapping] Save State = {SAVESTATE_KEY}")
    return changed


class IniSession:
    """Apply the driver settings for one PPSSPP session and put the previous ini files back afterwards."""

    def __init__(self, keep, **settings):
        self.settings = settings
        self.keep = keep
        self.snaps = []

    def __enter__(self):
        ensure_config_exists()
        for f in (INI, CONTROLS):
            if f.exists():
                snap = f.with_name(f.name + ".pre-ctl")
                shutil.copy2(f, snap)
                self.snaps.append((f, snap))
        for c in apply_driver_settings(**self.settings):
            log(f"ini: {c}")
        return self

    def __exit__(self, *exc):
        for f, snap in self.snaps:
            if not self.keep:
                shutil.copy2(snap, f)
            snap.unlink(missing_ok=True)
        log("ini: driver settings left in place" if self.keep else "ini: restored the pre-run ppsspp.ini and controls.ini")
        return False


# ---------------------------------------------------------------- process control

def ppsspp_pids():
    r = subprocess.run(["pgrep", "-x", "PPSSPPSDL"], capture_output=True, text=True)
    return [int(x) for x in r.stdout.split()]


def stop_process(pid, popen=None, timeout=15.0):
    """SIGTERM makes SDL post SDL_QUIT; PPSSPP then shuts down normally and saves its config."""
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return True
    t0 = time.time()
    while time.time() - t0 < timeout:
        if popen is not None:
            if popen.poll() is not None:
                return True
        else:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return True
        time.sleep(0.2)
    log(f"PPSSPP pid {pid} ignored SIGTERM for {timeout:.0f}s; sending SIGKILL")
    os.kill(pid, signal.SIGKILL)
    if popen is not None:
        popen.wait(5)
    return False


def launch(iso, logfile=None, stdout_path=None):
    if not APP.exists():
        die(f"{APP} not found (brew install --cask ppsspp-emulator)")
    iso = Path(iso)
    if not iso.exists():
        die(f"ISO {iso} does not exist (dangling disc.iso symlink?)")
    if ppsspp_pids():
        die(f"PPSSPPSDL is already running (pid {ppsspp_pids()}); quit it first or use the attach commands")
    cmd = [str(APP), "--windowed", "--pause-menu-exit"]
    if logfile:
        logfile = Path(logfile).resolve()
        logfile.parent.mkdir(parents=True, exist_ok=True)
        logfile.write_text("")      # PPSSPP appends to --log files; start each capture clean
        cmd.append(f"--log={logfile}")
    cmd.append(str(iso.resolve()))
    stdout_path = Path(stdout_path or OUTDIR / "ppsspp-stdout.log")
    stdout_path.parent.mkdir(parents=True, exist_ok=True)
    out = open(stdout_path, "w")
    log("launch: " + " ".join(cmd))
    return subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT, start_new_session=True)


def listening_ports(pid):
    r = subprocess.run(["lsof", "-nP", "-a", "-p", str(pid), "-iTCP", "-sTCP:LISTEN"], capture_output=True, text=True)
    return [int(m.group(1)) for m in re.finditer(r":(\d+) \(LISTEN\)", r.stdout)]


def find_port(pid, preferred, timeout=40.0, popen=None):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if popen is not None and popen.poll() is not None:
            die(f"PPSSPP exited early with code {popen.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", preferred), 0.5):
                return preferred
        except OSError:
            pass
        if pid and time.time() - t0 > 5:
            ports = listening_ports(pid)
            if ports:
                return ports[0]
        time.sleep(0.25)
    die(f"debugger port did not open within {timeout:.0f}s (is RemoteDebuggerOnStartup applied?)")


# ---------------------------------------------------------------- minimal RFC 6455 client (stdlib only)

def _xor_mask(data, mask):
    n = len(data)
    m = (mask * (n // 4 + 1))[:n]
    return (int.from_bytes(data, "little") ^ int.from_bytes(m, "little")).to_bytes(n, "little")


class WebSocket:
    GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    def __init__(self, host, port, path="/debugger", timeout=10.0):
        self.sock = socket.create_connection((host, port), timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        req = (f"GET {path} HTTP/1.1\r\nHost: {host}:{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
               f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
               f"Sec-WebSocket-Protocol: debugger.ppsspp.org\r\n\r\n")
        self.sock.sendall(req.encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("connection closed during handshake")
            buf += chunk
        head, _, self.pending = buf.partition(b"\r\n\r\n")
        status = head.split(b"\r\n", 1)[0]
        if b" 101 " not in status + b" ":
            raise ConnectionError(f"handshake refused: {status.decode(errors='replace')}")
        want = base64.b64encode(hashlib.sha1((key + self.GUID).encode()).digest())
        if want not in head:
            raise ConnectionError("bad Sec-WebSocket-Accept")
        self.sock.settimeout(None)
        self.wlock = threading.Lock()

    def _recv_exact(self, n):
        while len(self.pending) < n:
            chunk = self.sock.recv(max(65536, n - len(self.pending)))
            if not chunk:
                raise ConnectionError("socket closed")
            self.pending += chunk
        out, self.pending = self.pending[:n], self.pending[n:]
        return out

    def _send_frame(self, opcode, payload):
        hdr = bytearray([0x80 | opcode])
        n = len(payload)
        if n < 126:
            hdr.append(0x80 | n)
        elif n < 65536:
            hdr.append(0x80 | 126)
            hdr += struct.pack(">H", n)
        else:
            hdr.append(0x80 | 127)
            hdr += struct.pack(">Q", n)
        mask = os.urandom(4)
        with self.wlock:
            self.sock.sendall(bytes(hdr) + mask + _xor_mask(payload, mask))

    def send_text(self, text):
        self._send_frame(0x1, text.encode())

    def recv_message(self):
        """One complete text message (fragments joined), or None once the server closes."""
        parts = []
        while True:
            b0, b1 = self._recv_exact(2)
            fin, opcode = b0 & 0x80, b0 & 0x0F
            n = b1 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._recv_exact(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._recv_exact(8))[0]
            mask = self._recv_exact(4) if b1 & 0x80 else None
            payload = self._recv_exact(n)
            if mask:
                payload = _xor_mask(payload, mask)
            if opcode == 0x8:
                return None
            if opcode == 0x9:
                self._send_frame(0xA, payload)
                continue
            if opcode == 0xA:
                continue
            parts.append(payload)
            if fin:
                return b"".join(parts).decode("utf-8", "replace")

    def close(self):
        try:
            self._send_frame(0x8, b"\x03\xe8")
        except OSError:
            pass
        try:
            self.sock.close()
        except OSError:
            pass


class Debugger:
    """Request/response and event matching on top of the PPSSPP debugger socket."""

    def __init__(self, port, host="127.0.0.1"):
        self.ws = WebSocket(host, port)
        self.q = queue.Queue()
        self.stash = []
        self.ticket = 0
        threading.Thread(target=self._reader, daemon=True).start()

    def _reader(self):
        try:
            while True:
                m = self.ws.recv_message()
                if m is None:
                    break
                try:
                    self.q.put(json.loads(m))
                except json.JSONDecodeError:
                    self.q.put({"event": "_badjson", "raw": m[:200]})
        except (OSError, ConnectionError):
            pass
        self.q.put(None)

    def send(self, event, **params):
        self.ticket += 1
        self.ws.send_text(json.dumps({"event": event, "ticket": self.ticket, **params}))
        return self.ticket

    def wait(self, pred, timeout=10.0, what="event"):
        for i, m in enumerate(self.stash):
            if pred(m):
                return self.stash.pop(i)
        end = time.time() + timeout
        while True:
            left = end - time.time()
            if left <= 0:
                raise TimeoutError(f"timed out after {timeout:.1f}s waiting for {what}")
            try:
                m = self.q.get(timeout=left)
            except queue.Empty:
                continue
            if m is None:
                raise ConnectionError("debugger connection closed")
            if pred(m):
                return m
            if m.get("event") not in ("log", "input.buttons", "input.analog"):
                self.stash.append(m)
                del self.stash[:-200]

    def request(self, event, timeout=10.0, **params):
        t = self.send(event, **params)
        m = self.wait(lambda m: m.get("ticket") == t, timeout, f"reply to {event}")
        if m.get("event") == "error":
            raise RuntimeError(f"{event}: {m.get('message')}")
        return m

    def request_noreply(self, event, **params):
        """For requests without a direct reply: surface an immediate error, leave any later event in the stash."""
        t = self.send(event, **params)
        try:
            m = self.wait(lambda m: m.get("ticket") == t and m.get("event") == "error", 0.15, event)
            raise RuntimeError(f"{event}: {m.get('message')}")
        except TimeoutError:
            pass

    def drop(self, event):
        self.stash = [m for m in self.stash if m.get("event") != event]

    def wait_event(self, event, timeout=10.0):
        return self.wait(lambda m: m.get("event") == event and "ticket" not in m, timeout, event)

    # ---- helpers
    def usec(self):
        return self.request("cpu.evaluate", expression="usec")["uintValue"]

    def symbol(self, name):
        return self.request("cpu.evaluate", expression=name)["uintValue"]

    def stepping(self):
        return self.request("cpu.status")["stepping"]

    def regs(self, *names):
        return [self.request("cpu.getReg", name=n)["uintValue"] for n in names]

    def pause(self, timeout=10.0):
        # Core_Break is ignored unless the core is in CORE_RUNNING_CPU; between frames it sits in CORE_NEXTFRAME
        # (presenting/throttling), so a request can be dropped. Repeat it until the CPU reports stepping.
        end = time.time() + timeout
        while not self.stepping():
            if time.time() > end:
                raise TimeoutError("CPU did not enter stepping")
            self.drop("cpu.stepping")
            self.send("cpu.stepping")
            try:
                self.wait_event("cpu.stepping", 0.25)
            except TimeoutError:
                pass

    def resume(self):
        if self.stepping():
            self.drop("cpu.stepping")
            self.request_noreply("cpu.resume")

    def close(self):
        self.ws.close()


def connect(port, pid=None, popen=None, timeout=40.0):
    p = find_port(pid, port, timeout, popen)
    if p != port:
        log(f"debugger is on port {p} (configured {port} was busy)")
    t0 = time.time()
    while True:
        try:
            dbg = Debugger(p)
            break
        except (OSError, ConnectionError) as e:
            if time.time() - t0 > timeout:
                die(f"cannot open the debugger socket: {e}")
            time.sleep(0.3)
    # The server creates its broadcast switches on its first poll; until then this is refused, so retry.
    for _ in range(20):
        try:
            dbg.request("broadcast.config.set", disallowed={"logger": True, "input": True})
            break
        except RuntimeError:
            time.sleep(0.1)
    v = dbg.request("version", name="pure-recomp ppsspp_ctl", version=VERSION)
    log(f"connected to {v.get('name')} {v.get('version')} on port {p}")
    return dbg, p


def wait_boot(dbg, timeout=60.0):
    t0 = time.time()
    while time.time() - t0 < timeout:
        st = dbg.request("game.status")
        if st.get("game"):
            return st
        time.sleep(0.25)
    die("game did not finish booting")


# ---------------------------------------------------------------- framebuffer -> PNG

def write_png(path, width, height, rgb_rows):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + r for r in rgb_rows)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)
    return len(png)


def fb_to_rgb_rows(data, stride, fmt, width=480, height=272):
    """PSP display formats: 0 RGB565, 1 RGBA5551, 2 RGBA4444, 3 RGBA8888 (little-endian, R in the low bits)."""
    rows = []
    if fmt == 3:
        for y in range(height):
            row = data[y * stride * 4:(y * stride + width) * 4]
            out = bytearray(width * 3)
            out[0::3], out[1::3], out[2::3] = row[0::4], row[1::4], row[2::4]
            rows.append(bytes(out))
        return rows
    for y in range(height):
        px = struct.unpack_from(f"<{width}H", data, y * stride * 2)
        out = bytearray(width * 3)
        for i, p in enumerate(px):
            if fmt == 0:
                r, g, b = p & 31, (p >> 5) & 63, (p >> 11) & 31
                out[3 * i:3 * i + 3] = bytes(((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)))
            elif fmt == 1:
                r, g, b = p & 31, (p >> 5) & 31, (p >> 10) & 31
                out[3 * i:3 * i + 3] = bytes(((r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2)))
            else:
                r, g, b = p & 15, (p >> 4) & 15, (p >> 8) & 15
                out[3 * i:3 * i + 3] = bytes((r * 17, g * 17, b * 17))
        rows.append(bytes(out))
    return rows


def save_framebuffer(dbg, addr, stride, fmt, path):
    bpp = 4 if fmt == 3 else 2
    data = base64.b64decode(dbg.request("memory.read", timeout=30, address=addr, size=stride * 272 * bpp)["base64"])
    return write_png(path, 480, 272, fb_to_rgb_rows(data, stride, fmt))


# ---------------------------------------------------------------- run control and captures

def run_to(dbg, target_us, slack_us=50000):
    """Let the CPU run until about target_us, then pause (+-1 frame: the pause is asynchronous)."""
    dbg.resume()
    while True:
        u = dbg.usec()
        if u >= target_us - slack_us:
            dbg.pause()
            return dbg.usec()
        time.sleep(min(1.0, max(0.005, (target_us - slack_us - u) / 1e6 * 0.8)))


def wait_breakpoint(dbg, give_up_us, what):
    """Resume and wait for the next cpu.stepping; fail if emulated time passes give_up_us first."""
    dbg.drop("cpu.stepping")
    dbg.request_noreply("cpu.resume")
    while True:
        try:
            return dbg.wait_event("cpu.stepping", 1.0)
        except TimeoutError:
            if dbg.usec() > give_up_us:
                raise TimeoutError(f"no {what} before usec {give_up_us}")


def capture(dbg, setfb, frame_start_us, shot=None, gedump=None, renderer="software", patience_us=20_000_000,
            keep_stepping=False):
    """Capture the first frame the game draws after its first flip at or after frame_start_us.
    Flip k = first sceDisplaySetFrameBuf at/after the time; GE recording is armed there; flip k+1 hands over the
    finished frame k+1, whose pixels are read from VRAM at that call's address. Returns a report dict.
    Leaves the CPU running, or stepping with keep_stepping on a screenshot-only capture: the next capture then arms
    its breakpoint before the CPU runs again. Without that, a resume/pause round trip lets about 16 frames pass at
    real-time speed, and a capture requested sooner lands late by a host-dependent amount ("late_frames")."""
    rep = {}
    dbg.pause()
    dbg.request("cpu.breakpoint.add", address=setfb, condition=f"usec >= 0x{int(frame_start_us):x}")
    try:
        wait_breakpoint(dbg, frame_start_us + patience_us, "sceDisplaySetFrameBuf call")
        rep["flip_k_usec"] = u_k = dbg.usec()
        rep["flip_k_frame"] = round(frame_at_us(u_k), 3)
        if u_k - frame_start_us > 3 * FRAME_US:      # the CPU was already past the frame when the breakpoint went in
            rep["late_frames"] = round((u_k - frame_start_us) / FRAME_US, 1)
        before = set(DUMPDIR.glob("*.ppdmp")) if DUMPDIR.exists() else set()
        if gedump:
            dbg.drop("gpu.record.dump")
            dbg.request_noreply("gpu.record.dump")
        dbg.request("cpu.breakpoint.remove", address=setfb)
        dbg.request("cpu.breakpoint.add", address=setfb)
        wait_breakpoint(dbg, u_k + patience_us, "second sceDisplaySetFrameBuf call")
        rep["flip_usec"] = u = dbg.usec()
        rep["frame"] = round(frame_at_us(u), 3)
        addr, stride, fmt, sync = dbg.regs("a0", "a1", "a2", "a3")
        rep["framebuffer"] = {"addr": f"0x{addr:08x}", "stride": stride, "format": fmt, "sync": sync}
    finally:
        try:
            dbg.request("cpu.breakpoint.remove", address=setfb)
        except RuntimeError:
            pass
    if shot:
        if renderer != "software":
            rep["shot_error"] = "hardware renderer: VRAM does not hold the frame (use --renderer software)"
        else:
            rep["shot"] = str(Path(shot).resolve())
            rep["shot_bytes"] = save_framebuffer(dbg, addr, stride, fmt, shot)
    if gedump or not keep_stepping:
        dbg.resume()
    if gedump:
        m = dbg.wait(lambda m: m.get("event") == "gpu.record.dump" and "uri" in m, 60, "gpu.record.dump")
        head, _, b64 = m["uri"].partition(",")
        data = base64.b64decode(b64)
        Path(gedump).parent.mkdir(parents=True, exist_ok=True)
        Path(gedump).write_bytes(data)
        after = set(DUMPDIR.glob("*.ppdmp")) if DUMPDIR.exists() else set()
        new = sorted(after - before, key=lambda p: p.stat().st_mtime)
        rep["gedump"] = str(Path(gedump).resolve())
        rep["gedump_bytes"] = len(data)
        rep["ppsspp_dump_file"] = str(new[-1]) if new else None
    return rep


def save_state(pid, dest, timeout=20.0):
    """PPSSPP has no debugger event for save states, so press the Save State hotkey (F2, mapped in controls.ini)
    through CoreGraphics. That needs the Accessibility (post event) permission for the process running this."""
    cg = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    cg.CGPreflightPostEventAccess.restype = ctypes.c_bool
    if not cg.CGPreflightPostEventAccess():
        return None, ("blocked: this process may not post keyboard events (System Settings > Privacy & Security > "
                      "Accessibility for the terminal app); PPSSPP has no debugger event for save states")
    cg.CGEventCreateKeyboardEvent.restype = ctypes.c_void_p
    cg.CGEventCreateKeyboardEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint16, ctypes.c_bool]
    cg.CGEventPostToPid.argtypes = [ctypes.c_int, ctypes.c_void_p]
    snapshot = lambda: {p: p.stat().st_mtime for p in STATEDIR.glob("*.ppst")} if STATEDIR.exists() else {}
    before = snapshot()
    for down in (True, False):
        cg.CGEventPostToPid(pid, cg.CGEventCreateKeyboardEvent(None, MAC_KEYCODE_F2, down))
        time.sleep(0.1)
    t0 = time.time()
    while time.time() - t0 < timeout:
        fresh = [p for p, mt in snapshot().items() if before.get(p) != mt]
        if fresh:
            time.sleep(0.5)
            Path(dest).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(fresh[0], dest)
            return fresh[0], None
        time.sleep(0.25)
    return None, "no new .ppst appeared after pressing the Save State hotkey"


def parse_frame_path(spec):
    f, sep, p = spec.partition(":")
    if not sep or not f.isdigit() or not p:
        die(f"bad capture spec {spec!r} (want FRAME:PATH)")
    return int(f), p


# ---------------------------------------------------------------- commands

def cmd_run(a):
    script = "\n".join(Path(f).read_text() for f in a.pad_file) if a.pad_file else (a.pad or "")
    states = parse_pad_script(script)
    caps = {}
    for spec in a.shot or []:
        f, p = parse_frame_path(spec)
        caps.setdefault(f, {})["shot"] = p
    for spec in a.gedump or []:
        f, p = parse_frame_path(spec)
        caps.setdefault(f, {})["gedump"] = p
    if a.shots_every:
        if not a.until:
            die("--shots-every needs --until")
        d = Path(a.shots_dir or OUTDIR / "shots")
        start = a.shots_from or a.shots_every
        for f in range(start, a.until + 1, a.shots_every):
            caps.setdefault(f, {}).setdefault("shot", str(d / f"f{f:05d}.png"))
    end = max([a.until or 0] + list(caps) + [s[0] + 1 for s in states])
    if end <= 0:
        die("nothing to do: give --until, a capture or a pad script")
    if a.renderer != "software" and any("shot" in c for c in caps.values()):
        log("warning: screenshots need --renderer software; they will be skipped")
    log(f"pad states: {len(states)}; captures at frames {sorted(caps)}; run until frame {end}")

    report = {"tool": f"ppsspp_ctl {VERSION}", "iso": str(Path(a.iso).resolve()), "pad": script.strip(),
              "renderer": a.renderer, "rtc_base": a.rtc, "frame_us": FRAME_US, "vblank1_us": VBLANK1_US,
              "captures": []}
    t_wall = time.time()
    with IniSession(a.keep_ini or a.keep_running, port=a.port, renderer=a.renderer, hle_log=bool(a.log),
                    mute=not a.sound, savestate_key=bool(a.savestate)):
        p = launch(a.iso, a.log)
        dbg = None
        try:
            dbg, port = connect(a.port, p.pid, p)
            st = wait_boot(dbg)
            report["game"] = st["game"]
            log(f"game: {st['game']}")
            if not dbg.stepping():
                log(f"warning: CPU was not stopped at boot (AutoRun); script starts late at usec {dbg.usec()}")
            report["boot_usec"] = dbg.usec()
            if a.rtc:
                dbg.request("replay.time.set", value=a.rtc)
            blob = build_replay_blob(states)
            dbg.request("replay.execute", version=1, base64=base64.b64encode(blob).decode())
            report["replay_items"] = len(blob) // 17
            setfb = dbg.symbol(SETFB_STUB)
            report["setfb_stub"] = f"0x{setfb:08x}"
            for frame in sorted(caps):
                c = caps[frame]
                rep = capture(dbg, setfb, vblank_us(frame), c.get("shot"), c.get("gedump"), a.renderer,
                              keep_stepping=True)
                rep["requested_frame"] = frame
                report["captures"].append(rep)
                what = ", ".join(f"{k} {Path(v).name}" for k, v in c.items())
                log(f"frame {frame}: captured frame {rep['frame']} (flip at usec {rep['flip_usec']}, "
                    f"fb {rep['framebuffer']['addr']}) -> {what}; wall {time.time() - t_wall:.0f}s")
                if rep.get("late_frames"):
                    log(f"  late: the first flip was {rep['late_frames']} frames after the requested frame")
                if rep.get("shot_error"):
                    log(f"  screenshot skipped: {rep['shot_error']}")
                if c.get("gedump"):
                    log(f"  GE dump {rep['gedump_bytes']} bytes; PPSSPP's copy: {rep['ppsspp_dump_file']}")
            u = run_to(dbg, vblank_us(end))
            report["end_usec"] = u
            report["end_frame"] = round(frame_at_us(u), 2)
            log(f"reached frame {report['end_frame']} (usec {u}); wall {time.time() - t_wall:.0f}s")
            if a.savestate:
                dbg.resume()
                own, err = save_state(p.pid, a.savestate)
                report["savestate"] = {"path": a.savestate, "ppsspp_file": str(own) if own else None, "error": err}
                log(f"save state: {err or f'{own} -> {a.savestate}'}")
            if a.keep_running:
                dbg.resume()
        except Exception as e:  # report, then still shut PPSSPP down
            report["error"] = f"{type(e).__name__}: {e}"
            log(f"error: {report['error']}")
        finally:
            if dbg:
                dbg.close()
            if a.keep_running:
                log(f"leaving PPSSPP running (pid {p.pid}); the driver settings stay in ppsspp.ini")
            else:
                clean = stop_process(p.pid, p)
                report["quit"] = "clean" if clean else "killed"
                log("PPSSPP quit cleanly" if clean else "PPSSPP had to be killed")
    report["wall_seconds"] = round(time.time() - t_wall, 1)
    if a.report:
        Path(a.report).parent.mkdir(parents=True, exist_ok=True)
        Path(a.report).write_text(json.dumps(report, indent=2) + "\n")
        log(f"report -> {a.report}")
    if "error" in report:
        sys.exit(1)


def cmd_launch(a):
    for c in apply_driver_settings(a.port, a.renderer, bool(a.log), not a.sound):
        log(f"ini: {c}")
    p = launch(a.iso, a.log)
    dbg, port = connect(a.port, p.pid, p)
    st = wait_boot(dbg)
    if a.run:
        dbg.resume()
    log(f"pid {p.pid}, debugger port {port}, game {st['game']}, CPU {'stepping' if dbg.stepping() else 'running'}")
    log("the driver settings stay in ppsspp.ini until `ini restore`")
    dbg.close()


def attach(a):
    pids = ppsspp_pids()
    if not pids:
        die("PPSSPPSDL is not running")
    dbg, _ = connect(a.port, pids[0], timeout=5.0)
    return dbg, pids[0]


def current_renderer():
    return "software" if Ini(INI).get("Graphics", "SoftwareRenderer") == "True" else "hardware"


def cmd_status(a):
    dbg, pid = attach(a)
    st = dbg.request("game.status")
    st.pop("ticket", None)
    print(json.dumps(st, indent=2))
    if st.get("game"):
        cs = dbg.request("cpu.status")
        u = dbg.usec()
        print(json.dumps({"pid": pid, "stepping": cs["stepping"], "paused": cs["paused"], "pc": f"0x{cs['pc']:08x}",
                          "ticks": cs["ticks"], "usec": u, "frame": round(frame_at_us(u), 3),
                          "replay": {k: v for k, v in dbg.request("replay.status").items() if k != "ticket"}},
                         indent=2))
    dbg.close()


def cmd_shot(a, gedump=None):
    dbg, _ = attach(a)
    setfb = dbg.symbol(SETFB_STUB)
    dbg.pause()
    shot = a.path if not gedump else str(Path(gedump).with_suffix(".png"))
    rep = capture(dbg, setfb, dbg.usec(), shot, gedump, current_renderer())
    print(json.dumps(rep, indent=2))
    dbg.close()


def cmd_gedump(a):
    cmd_shot(a, gedump=a.path)


def cmd_press(a):
    """Exploration helper: hold buttons on a running game for N frames (paced by emulated time, not frame-exact)."""
    dbg, _ = attach(a)
    names = [n.strip().upper() for n in re.split(r"[+|,]", a.buttons) if n.strip()]
    ws_names = {"L": "ltrigger", "R": "rtrigger", "LTRIGGER": "ltrigger", "RTRIGGER": "rtrigger"}
    btn = {ws_names.get(n, n.lower()): True for n in names}
    dbg.resume()
    u0 = dbg.usec()
    dbg.request("input.buttons.send", buttons=btn)
    while dbg.usec() < u0 + a.frames * FRAME_US:
        time.sleep(0.005)
    dbg.request("input.buttons.send", buttons={k: False for k in btn})
    log(f"held {'+'.join(names)} from frame {frame_at_us(u0):.1f} for {a.frames} frames")
    dbg.close()


def cmd_quit(a):
    pids = ppsspp_pids()
    if not pids:
        log("PPSSPPSDL is not running")
    for pid in pids:
        log(f"pid {pid}: {'quit cleanly' if stop_process(pid) else 'killed'}")


def cmd_ini(a):
    if a.action == "apply":
        for c in apply_driver_settings(a.port, a.renderer, a.hle_log, not a.sound) or ["(already applied)"]:
            log(f"ini: {c}")
    elif a.action == "restore":
        if ppsspp_pids():
            die("quit PPSSPP first (it rewrites ppsspp.ini on exit)")
        for f in (INI, CONTROLS):
            orig = f.with_name(f.name + ".orig")
            if orig.exists():
                shutil.copy2(orig, f)
                log(f"restored {f} from {orig.name}")
    else:
        ini = Ini(INI)
        for group in (DRIVER_SETTINGS, MUTE_SETTINGS):
            for section, kv in group.items():
                for k in kv:
                    print(f"[{section}] {k} = {ini.get(section, k)}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=DEFAULT_PORT, help="debugger port written to RemoteISOPort")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def common(p):
        p.add_argument("--iso", default=str(DEFAULT_ISO))
        p.add_argument("--log", metavar="FILE", help="PPSSPP log file; also raises the HLE log categories")
        p.add_argument("--renderer", choices=["software", "hardware"], default="software",
                       help="software (default) keeps frames in VRAM so screenshots work; hardware = Vulkan")
        p.add_argument("--sound", action="store_true", help="keep game volume (default: GameVolume 0)")

    r = sub.add_parser("run", help="boot, play a pad script, capture, quit")
    common(r)
    r.add_argument("--pad", help="inline pad script, e.g. '120:CROSS,130:'")
    r.add_argument("--pad-file", action="append",
                   help="pad script file (routes/*.txt); repeat to chain routes (frames stay absolute)")
    r.add_argument("--shot", action="append", metavar="FRAME:PNG", help="screenshot of the capture at FRAME")
    r.add_argument("--gedump", action="append", metavar="FRAME:PPDMP", help="GE recording of the capture at FRAME")
    r.add_argument("--shots-every", type=int, metavar="N", help="also screenshot every N frames up to --until")
    r.add_argument("--shots-from", type=int, metavar="F", help="first frame for --shots-every (default N)")
    r.add_argument("--shots-dir", help="directory for --shots-every (default out/ppsspp/shots)")
    r.add_argument("--until", type=int, metavar="FRAME", help="run at least until this frame")
    r.add_argument("--savestate", metavar="FILE", help="save a state at the end (needs keyboard-event permission)")
    r.add_argument("--rtc", type=int, default=1767225600, help="PSP RTC base, unix seconds (0 = host clock)")
    r.add_argument("--keep-ini", action="store_true", help="leave the driver settings in ppsspp.ini afterwards")
    r.add_argument("--keep-running", action="store_true", help="do not quit PPSSPP at the end")
    r.add_argument("--report", metavar="JSON", help="write a JSON report of the run")
    r.set_defaults(fn=cmd_run)

    l = sub.add_parser("launch", help="boot with the debugger on and leave PPSSPP running (CPU stopped at boot)")
    common(l)
    l.add_argument("--run", action="store_true", help="resume the CPU after the boot break")
    l.set_defaults(fn=cmd_launch)

    s = sub.add_parser("status", help="print game.status of the running PPSSPP")
    s.set_defaults(fn=cmd_status)
    s = sub.add_parser("shot", help="capture the next frame of the running game to a PNG")
    s.add_argument("path")
    s.set_defaults(fn=cmd_shot)
    s = sub.add_parser("gedump", help="GE-record the next frame of the running game (and a PNG of it)")
    s.add_argument("path")
    s.set_defaults(fn=cmd_gedump)
    s = sub.add_parser("press", help="hold buttons on the running game for a few frames (exploration only)")
    s.add_argument("buttons", help="e.g. CROSS or UP+CROSS")
    s.add_argument("--frames", type=int, default=6)
    s.set_defaults(fn=cmd_press)
    s = sub.add_parser("quit", help="quit PPSSPP cleanly")
    s.set_defaults(fn=cmd_quit)
    s = sub.add_parser("ini", help="apply | restore (.orig) | show the driver settings")
    s.add_argument("action", choices=["apply", "restore", "show"])
    s.add_argument("--renderer", choices=["software", "hardware"], default="software")
    s.add_argument("--hle-log", action="store_true")
    s.add_argument("--sound", action="store_true")
    s.set_defaults(fn=cmd_ini)

    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
