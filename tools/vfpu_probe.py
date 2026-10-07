#!/opt/homebrew/bin/python3
"""VFPU operand probe (task 047): PPSSPP's VFPU operands and results at chosen instructions, as CSV rows of bits.

  vfpu_probe.py scan [--kinds K,...]              the dot-product and transcendental sites of EBOOT.ELF
  vfpu_probe.py cover [--track T] [--seconds S]   which of them a race executes, and how often (PPSSPP)
  vfpu_probe.py sample [--track T] [--seconds S] [--sites all|auto|ADDR,...] [--cap N] [--cpu-core 0|1] [--out DIR]
                                                  operands and results at the sites, one CSV a site (PPSSPP)
  vfpu_probe.py port [DIR]                        the port's results for the same operands, from the corpus's own
                                                  code for each site, compiled with the corpus's flags

How the PPSSPP side works. The route is the scorecard's reference route for the circuit (tools/scorecard.py
pp_routes: the frontend, the circuit, Cross held from READY), so the race is the reference race the race clock of
task 046 was taken from (PPSSPP repeats a route exactly). At boot, before the JIT has compiled anything, the probe
puts log-only breakpoints (they never stop the CPU) on every site and on the instruction after it, each with the
condition `usec >= READY` (and an end for a hot site, which logs for a shorter span from GO); a breakpoint added later,
while the CPU runs, never fires in a block PPSSPP's JIT has already compiled. The first logs the source lanes the
encoding names (`cpu.evaluate` and the breakpoint log both take PPSSPP's scalar names, S000 to S733), the second the
destination lanes, which is the state one step later. A site in a branch delay slot gets its second breakpoint at the
branch's target (and at the fall-through for a conditional branch); a site after `jr` or `jalr` is skipped. A result
line counts only when the line just before it in PPSSPP's log is its own site's operand line, so a pair is always
one execution. The run ends when the player's race clock reaches --seconds; every ship's position is then compared
with the scorecard's reference race. With PPSSPP's interpreter (`--cpu-core 0`) a log-only breakpoint stops the CPU,
so the probe steps instead: it reads the registers at each stop (cpu.getAllRegs) and resumes, about 90 stops a second.
The ini (and so the CPU core) is put back after every run; this machine's PPSSPP runs the JIT (CPUCore = 1).

The prefix registers (VPFXS, VPFXT, VPFXD) are not registers PPSSPP's debugger exposes (cpu.getAllRegs offers GPR,
FPU and the 128 VFPU scalars; checked 2026-10-07): they are set by the vpfx instructions just before an instruction,
so the probe decodes them from the code (up to three words back) and writes them into sites.json; an instruction with
no prefix word before it runs with the identity prefixes (S and T 0xE4, D 0).

Files (ref/vfpu/ by default; git-ignored, hashes in ref/README.md):
  sites.json        every sampled site: word, mnemonic, lanes (PPSSPP names), prefixes, function, rows
  <ADDR>.csv        `usec,s0..,t0..,d0..` in hex (s source lanes, t target lanes, d destination lanes after)
  <ADDR>.port.csv   (port) the port's destination lanes for the same rows
  coverage.csv      (cover) hits per site over the covered race window; coverage.json, the run
  A set a PPSSPP core: ref/vfpu/jit/ (core 1) and ref/vfpu/interp/ (core 0); coverage.* in ref/vfpu/ serves both.

PPSSPP's memory stick: the routes answer NO to SAVE PROFILE; the probe compares PSP/SAVEDATA before and after and
moves anything new out to out/vfpu_probe/savedata-moved/ (none so far). Python 3 standard library only.
"""
import argparse, bisect, csv, json, re, struct, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "ppsspp"))

ELF = ROOT / "game" / "EBOOT.ELF"
LOAD_BASE = 0x08804000                     # the PRX's load address (the function map starts there)
OUT = ROOT / "ref" / "vfpu"
WORK = ROOT / "out" / "vfpu_probe"
TASK046_SITES = (0x089196B8, 0x08926E08)   # the two vdot.t sites task 046 compared

UNARY = {16: "vrcp", 17: "vrsq", 18: "vsin", 19: "vcos", 20: "vexp2", 21: "vlog2", 22: "vsqrt", 23: "vasin",
         24: "vnrcp", 26: "vnsin", 28: "vrexp2"}
DOT_KINDS = ("vdot", "vhdp", "vmmul", "vtfm")
# Task 048: the products and sums beside the dot forms (execute_vfpu_cross_quat, execute_vfpu_horizontal,
# execute_vfpu_vrot, execute_vfpu_vmscl, and vcrs.t, which the codegen emits inline).
NEW_KINDS = ("vcrs", "vcrsp", "vqmul", "vfad", "vavg", "vrot", "vmscl")
CORES = {0: "interpreter", 1: "JIT", 2: "IR interpreter", 3: "JIT using IR"}


def say(msg):
    print(f"[vfpu_probe] {msg}", flush=True)


# ------------------------------------------------------------------------------------------- the code

def load_text(path=ELF):
    """EBOOT.ELF's first loadable segment as words, addressed from LOAD_BASE."""
    d = Path(path).read_bytes()
    if d[:4] != b"\x7fELF":
        sys.exit(f"vfpu_probe: {path} is not an ELF (run tools/setup_game.sh)")
    phoff, = struct.unpack_from("<I", d, 28)
    phnum, = struct.unpack_from("<H", d, 44)
    for i in range(phnum):
        p_type, p_offset, p_vaddr, _, p_filesz, _, _, _ = struct.unpack_from("<8I", d, phoff + 32 * i)
        if p_type == 1:
            return LOAD_BASE + p_vaddr, struct.unpack_from(f"<{p_filesz // 4}I", d, p_offset)
    sys.exit("vfpu_probe: no loadable segment")


def function_map():
    rows = []
    for r in csv.DictReader(open(ROOT / "config" / "function_map.csv")):
        rows.append((int(r["start"], 16), int(r["end"], 16), r["name"]))
    rows.sort()
    starts = [r[0] for r in rows]

    def name(a):
        i = bisect.bisect_right(starts, a) - 1
        return rows[i][2] if i >= 0 and rows[i][0] <= a <= rows[i][1] else None
    return name


def scalar_name(r):
    """PPSSPP's (and the PSP assembler's) name of scalar register r, encoded 0YYMMMXX: S<matrix><X><Y>."""
    return f"S{(r >> 2) & 7}{r & 3}{(r >> 5) & 3}"


def vector_lanes(v, n):
    """The scalar registers of the n-lane vector register v, in lane order (as the framework's read_vfpu_vector)."""
    if n == 1:
        return [v & 0x7F]
    m, col = (v >> 2) & 7, v & 3
    row = ((v >> 6) & 1) if n == 3 else ((v >> 5) & 2)
    if (v >> 5) & 1:
        return [(col << 5) | (m << 2) | ((row + i) & 3) for i in range(n)]
    return [(((row + i) & 3) << 5) | (m << 2) | col for i in range(n)]


def matrix_lanes(v, side):
    """The scalars of the side x side matrix register v, as element [j * side + i] of the framework's
    read_vfpu_matrix (its destination[j * 4 + i]); j is the codegen's row index in vtfm and vmmul."""
    m, col = (v >> 2) & 7, v & 3
    transpose = (v >> 5) & 1
    if side == 1:
        transpose, row = 0, (v >> 5) & 3
    elif side == 3:
        row = (v >> 6) & 1
    else:
        row = (v >> 5) & 2
    out = []
    for j in range(side):
        for i in range(side):
            if transpose:
                out.append((((col + j) & 3) << 5) | (m << 2) | ((row + i) & 3))
            else:
                out.append((((row + i) & 3) << 5) | (m << 2) | ((col + j) & 3))
    return out


def decode(word):
    """The sites this tool knows: a dict with the mnemonic and the lanes, or None."""
    top9 = word >> 23
    size = ((word >> 7) & 1) | (((word >> 15) & 1) << 1)
    n = size + 1
    vd, vs, vt = word & 0x7F, (word >> 8) & 0x7F, (word >> 16) & 0x7F
    if top9 in (0b011001001, 0b011001100):
        kind = "vdot" if top9 == 0b011001001 else "vhdp"
        return {"kind": kind, "mnemonic": f"{kind}.{'sptq'[size]}", "length": n,
                "s": vector_lanes(vs, n), "t": vector_lanes(vt, n), "d": vector_lanes(vd, 1)}
    if top9 == 0b111100000:
        return {"kind": "vmmul", "mnemonic": f"vmmul.{'sptq'[size]}", "length": n,
                "s": matrix_lanes(vs, n), "t": matrix_lanes(vt, n), "d": matrix_lanes(vd, n)}
    if top9 in (0b111100001, 0b111100010, 0b111100011):
        side = (top9 & 3) + 1
        name = f"vtfm{side}" if n == side else f"vhtfm{side}"
        return {"kind": "vtfm", "mnemonic": f"{name}.{'sptq'[size]}", "length": n, "side": side,
                "s": matrix_lanes(vs, side), "t": vector_lanes(vt, n), "d": vector_lanes(vd, side)}
    if top9 == 0b110100000 and ((word >> 16) & 0x7F) in UNARY:
        op = UNARY[(word >> 16) & 0x7F]
        return {"kind": op, "mnemonic": f"{op}.{'sptq'[size]}", "length": n,
                "s": vector_lanes(vs, n), "t": [], "d": vector_lanes(vd, n)}
    # Task 048's kinds (the decoder of vendor/portablekit/src/decoder.cpp, the encodings of vfpu-docs).
    if top9 == 0b011001101 and n == 3:                   # vcrs.t: (s.y*t.z, s.z*t.x, s.x*t.y), triples only
        return {"kind": "vcrs", "mnemonic": "vcrs.t", "length": 3,
                "s": vector_lanes(vs, 3), "t": vector_lanes(vt, 3), "d": vector_lanes(vd, 3)}
    if top9 == 0b111100101 and n in (3, 4):              # vcrsp.t (the cross product), vqmul.q (quaternions)
        kind = "vcrsp" if n == 3 else "vqmul"
        return {"kind": kind, "mnemonic": f"{kind}.{'sptq'[size]}", "length": n,
                "s": vector_lanes(vs, n), "t": vector_lanes(vt, n), "d": vector_lanes(vd, n)}
    if word >> 21 == 0b11010000010 and ((word >> 16) & 31) in (6, 7) and n >= 2:   # vfad, vavg: one sum
        kind = "vfad" if ((word >> 16) & 31) == 6 else "vavg"
        return {"kind": kind, "mnemonic": f"{kind}.{'sptq'[size]}", "length": n,
                "s": vector_lanes(vs, n), "t": [], "d": vector_lanes(vd, 1)}
    if word >> 21 == 0b11110011101:                     # vrot: a rotation row from the scalar angle vs
        return {"kind": "vrot", "mnemonic": f"vrot.{'sptq'[size]}", "length": n, "imm": (word >> 16) & 31,
                "s": vector_lanes(vs, 1), "t": [], "d": vector_lanes(vd, n)}
    if top9 == 0b111100100:                              # vmscl: a matrix times the scalar vt
        return {"kind": "vmscl", "mnemonic": f"vmscl.{'sptq'[size]}", "length": n, "side": n,
                "s": matrix_lanes(vs, n), "t": vector_lanes(vt, 1), "d": matrix_lanes(vd, n)}
    return None


def prefixes(words, base, addr):
    """The vpfxs/vpfxt/vpfxd words just before addr (a prefix applies to the next VFPU instruction)."""
    out = {}
    for k in range(1, 4):
        w = words[(addr - base) // 4 - k]
        if w >> 24 in (0xDC, 0xDD, 0xDE):
            out.setdefault({0xDC: "s", 0xDD: "t", 0xDE: "d"}[w >> 24], w & 0xFFFFFF)
        else:
            break
    return out


def next_pcs(words, base, addr):
    """Where execution goes after addr: [addr + 4], or for a delay slot the branch's targets; None for jr/jalr."""
    w = words[(addr - base) // 4 - 1]
    op = w >> 26
    rel = addr + ((w & 0xFFFF) - (0x10000 if w & 0x8000 else 0)) * 4     # target of a branch at addr - 4
    if op == 0 and (w & 0x3F) in (8, 9):
        return None
    if op in (2, 3):
        return [((addr - 4) & 0xF0000000) | ((w & 0x3FFFFFF) << 2)]
    rt = (w >> 16) & 31
    if op in (4, 5, 6, 7) or (op == 1 and rt in (0, 1, 16, 17)):
        return sorted({rel, addr + 4})
    if op in (20, 21, 22, 23) or (op == 1 and rt in (2, 3, 18, 19)):
        return [rel]                                    # a likely branch runs its delay slot only when taken
    if op in (0x11, 0x12) and ((w >> 21) & 31) == 8:
        likely = (w >> 17) & 1
        return [rel] if likely else sorted({rel, addr + 4})
    return [addr + 4]


def scan(kinds=None, reachable_only=True):
    base, words = load_text()
    fname = function_map()
    labels = reachable_addresses() if reachable_only else None
    sites = []
    for i, w in enumerate(words):
        a = base + 4 * i
        d = decode(w)
        if not d or (kinds and d["kind"] not in kinds):
            continue
        if labels is not None and a not in labels:
            continue
        d.update(addr=a, word=w, function=fname(a), prefixes=prefixes(words, base, a), next=next_pcs(words, base, a))
        sites.append(d)
    return sites


def reachable_addresses():
    """The instruction addresses the corpus has code for (its L_XXXXXXXX labels): decoded data is left out."""
    gen = ROOT / "generated"
    labels = set()
    for f in sorted(gen.glob("generated_unit_*.cpp")):
        for m in re.finditer(r"^L_([0-9A-F]{8}):", f.read_text(), re.M):
            labels.add(int(m.group(1), 16))
    if not labels:
        sys.exit("vfpu_probe: generated/ has no corpus (tools/worktree_init.sh)")
    return labels


def site_json(s):
    return {"addr": f"0x{s['addr']:08X}", "word": f"0x{s['word']:08X}", "mnemonic": s["mnemonic"],
            "kind": s["kind"], "length": s["length"], **({"side": s["side"]} if "side" in s else {}),
            **({"imm": s["imm"]} if "imm" in s else {}),
            "function": s["function"], "prefixes": {k: f"0x{v:06X}" for k, v in s["prefixes"].items()},
            "next": [f"0x{a:08X}" for a in s["next"]] if s["next"] else None,
            "s": [scalar_name(r) for r in s["s"]], "t": [scalar_name(r) for r in s["t"]],
            "d": [scalar_name(r) for r in s["d"]]}


def cmd_scan(a):
    sites = scan(a.kinds.split(",") if a.kinds else None)
    for s in sites:
        j = site_json(s)
        pf = " ".join(f"{k}={v}" for k, v in j["prefixes"].items())
        print(f"{j['addr']} {j['word']} {j['mnemonic']:10} {str(j['function']):24} "
              f"s={','.join(j['s'])} t={','.join(j['t'])} d={','.join(j['d'])} {pf}"
              f"{'' if s['next'] == [s['addr'] + 4] else ' next=' + str(j['next'])}")
    say(f"{len(sites)} sites")


# ------------------------------------------------------------------------------------------- PPSSPP runs

def stick_snapshot():
    import ppsspp_ctl as pc
    d = pc.MEMSTICK / "PSP" / "SAVEDATA"
    return {p.name: p.stat().st_mtime for p in d.iterdir()} if d.exists() else {}


def stick_restore(before):
    """Anything the run added to PPSSPP's SAVEDATA goes to out/vfpu_probe/savedata-moved/; changes are reported."""
    import shutil
    import ppsspp_ctl as pc
    d = pc.MEMSTICK / "PSP" / "SAVEDATA"
    after = stick_snapshot()
    for name in sorted(set(after) - set(before)):
        dest = WORK / "savedata-moved" / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(d / name), str(dest))
        say(f"memory stick: the run wrote {name}; moved to {dest}")
    for name in sorted(n for n in before if n in after and after[n] != before[n]):
        say(f"memory stick: warning: {name} changed during the run")
    for name in sorted(set(before) - set(after)):
        say(f"memory stick: warning: {name} disappeared during the run")


def ppsspp_race(track, logfile, breakpoints, seconds, cpu_core=None, wall_limit=3600.0):
    """The reference route for `track` with log-only breakpoints logging from READY: breakpoints is a list of
    (address, logFormat[, (start_us, length_us)]); with a span a breakpoint logs only from start_us after READY for
    length_us. Runs until the player's race clock reaches `seconds`. Returns a summary dict.

    PPSSPP's interpreter (CPU core 0) stops at a log-only breakpoint as at any other (checked 2026-10-07), so with
    that core the probe steps instead: every breakpoint stops the CPU, the probe reads the registers its logFormat
    names (cpu.getAllRegs), writes the line PPSSPP would have logged to <log>.steps.log and resumes."""
    import base64
    import ppsspp_ctl as pc
    import pp_lines as pl
    import scorecard as sc
    files, hold = sc.pp_routes(track)
    script = ("\n".join((sc.PP_ROUTES / f).read_text() for f in files)
              + f"\n{hold}:CROSS\n{hold + sc.PP_HOLD_VBLANKS}:\n")
    states = pc.parse_pad_script(script)
    if not sc.wait_ppsspp():
        raise RuntimeError("PPSSPP did not become free")
    before = stick_snapshot()
    rec = pl.RECORD_POS + sc.PLAYER * pl.STRIDE
    t0 = time.time()
    out = {"track": track, "route": files, "ready_vblank": hold}
    try:
        with pc.IniSession(False, port=pc.DEFAULT_PORT, renderer="hardware", hle_log=False, mute=True,
                           savestate_key=False):
            ini = pc.Ini(pc.INI)
            if cpu_core is not None:
                # For this session only (IniSession puts the previous ini back afterwards): 0 the interpreter, 1 the
                # JIT (this machine's setting, which every reference of ref/ was taken with), 2 the IR interpreter.
                ini.set("CPU", "CPUCore", str(cpu_core))
                ini.save()
            out["cpu_core"] = int(pc.Ini(pc.INI).get("CPU", "CPUCore") or -1)
            say(f"PPSSPP's CPU core: {out['cpu_core']} ({CORES.get(out['cpu_core'], '?')})")
            proc = pc.launch(pc.DEFAULT_ISO, str(logfile))
            dbg = None
            try:
                dbg, _ = pc.connect(pc.DEFAULT_PORT, proc.pid, proc)
                pc.wait_boot(dbg)
                dbg.request("replay.time.set", value=sc.RTC)
                dbg.request("replay.execute", version=1,
                            base64=base64.b64encode(pc.build_replay_blob(states)).decode())
                # Armed at boot, before any of the code is compiled, with a condition that keeps them quiet until
                # READY: a breakpoint added later, while the CPU runs, does not reach a block PPSSPP's JIT has
                # already compiled (the first coverage run, armed at READY, saw none of the ship update's calls).
                arm = int(pc.vblank_us(hold))
                out["armed_usec"], out["armed_vblank"] = arm, hold
                stepping = out["cpu_core"] == 0
                out["stepping"] = stepping
                names_at = {bp[0]: re.findall(r"\{(S\d{3}):x\}", bp[1]) for bp in breakpoints}
                steps = open(Path(str(logfile) + ".steps.log"), "w") if stepping else None
                vidx, nstops, last_check = None, 0, 0.0
                for bp in breakpoints:
                    addr, fmt = bp[0], bp[1]
                    span = bp[2] if len(bp) > 2 else None
                    if span:
                        start, length = span
                        cond = f"usec >= 0x{arm + start:x} && usec < 0x{arm + start + length:x}"
                    else:
                        cond = f"usec >= 0x{arm:x}"
                    if stepping:
                        dbg.request("cpu.breakpoint.add", address=addr, enabled=True, condition=cond)
                    else:
                        dbg.request("cpu.breakpoint.add", address=addr, enabled=False, log=True, logFormat=fmt,
                                    condition=cond)
                say(f"{len(breakpoints)} {'stepping' if stepping else 'log'} breakpoints armed at boot, active from "
                    f"vblank {hold} (READY)")
                dbg.resume()
                clock, end = 0.0, None
                while True:
                    if time.time() - t0 > wall_limit:
                        raise RuntimeError("wall-clock limit reached")
                    if stepping:
                        try:
                            ev = dbg.wait_event("cpu.stepping", 0.5)
                        except TimeoutError:
                            st = dbg.request("cpu.status")      # a stop whose event went missing
                            ev = {"pc": st["pc"], "ticks": st["ticks"]} if st["stepping"] else None
                        if ev is not None and ev.get("pc") in names_at:
                            cat = dbg.request("cpu.getAllRegs")["categories"][2]
                            if vidx is None:
                                vidx = {n: i for i, n in enumerate(cat["registerNames"])}
                            vals = cat["uintValues"]
                            steps.write(f"BKP PC={ev['pc']:08x}: VP {ev['ticks'] // 222} "
                                        + " ".join(f"{vals[vidx[n]]:x}" for n in names_at[ev["pc"]]) + "\n")
                            dbg.drop("cpu.resume")
                            dbg.send("cpu.resume")
                            nstops += 1
                            if time.time() - last_check < 2.0:
                                continue
                        last_check = time.time()
                    frame = pc.frame_at_us(dbg.usec())
                    if frame < hold:
                        time.sleep(min(2.0, max(0.05, (hold - frame) / 60 * 0.8)))
                        continue
                    a = dbg.request("memory.read", address=rec, size=0x20)["base64"]
                    b = dbg.request("memory.read", address=rec, size=0x20)["base64"]
                    if a == b:
                        raw = base64.b64decode(a)
                        clock = struct.unpack_from("<f", raw, 0x1C)[0]
                        if clock >= seconds:
                            end = (clock,) + struct.unpack_from("<3f", raw, 0)
                            dbg.pause()
                            out["end_usec"] = dbg.usec()
                            blk = base64.b64decode(dbg.request("memory.read", address=pl.RECORD_POS,
                                                               size=8 * pl.STRIDE)["base64"])
                            ships = {k: struct.unpack_from("<3f", blk, k * pl.STRIDE)
                                     + (struct.unpack_from("<f", blk, k * pl.STRIDE + 0x1C)[0],)
                                     for k in range(8)}
                            break
                    if stepping:
                        continue                           # a stop meanwhile is the next event of the loop
                    if frame > hold + 1500 and clock <= 0.0:
                        raise RuntimeError("no race clock: the route did not reach a race")
                    time.sleep(0.25)
            finally:
                if steps:
                    steps.close()
                    out["stops"] = nstops
                if dbg:
                    dbg.close()
                pc.stop_process(proc.pid, proc)
    finally:
        stick_restore(before)
    out["end_clock"], out["end_player"] = end[0], list(end[1:])
    out["wall_seconds"] = round(time.time() - t0, 1)
    # Is this the reference race? Every ship's position at the end against the scorecard's PPSSPP reference (task
    # 044's, taken without breakpoints) at the same clock: the probe's breakpoints must not change the race.
    import math
    refs = sc.read_pp_samples(sc.REF / "trajectories" / f"{track}.csv")
    offs = {}
    for k, (x, y, z, c) in ships.items():
        ref = refs.get(k, [])
        q = sc.interp(ref, [p_[0] for p_ in ref], c) if ref else None
        if q:
            offs[k] = round(math.dist((x, y, z), q), 4)
    if sc.PLAYER in offs:
        out["player_off_reference_m"] = offs[sc.PLAYER]
    out["ships_off_reference_m"] = offs
    return out


BKP_RE = re.compile(r"BKP PC=([0-9a-fA-F]{8}): (V[CP])(?: (.*))?$")


def cmd_cover(a):
    sites = scan(a.kinds.split(",") if a.kinds else None)
    WORK.mkdir(parents=True, exist_ok=True)
    log = WORK / f"cover_{a.track}.log"
    bps = [(s["addr"], "VC") for s in sites]
    if a.reuse_log and log.exists():
        info = json.loads((Path(a.out) / "coverage.json").read_text()) if (Path(a.out) / "coverage.json").exists() \
            else {"track": a.track}
        say(f"reusing {log}")
    else:
        say(f"covering {len(sites)} sites on {a.track} to race clock {a.seconds} s")
        info = ppsspp_race(a.track, log, bps, a.seconds, a.cpu_core)
    hits = {}
    for line in open(log, errors="replace"):
        m = BKP_RE.search(line)
        if m and m[2] == "VC":
            pc_ = int(m[1], 16)
            hits[pc_] = hits.get(pc_, 0) + 1
    dest = Path(a.out) / "coverage.csv"
    dest.parent.mkdir(parents=True, exist_ok=True)
    with open(dest, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["addr", "mnemonic", "function", "hits", "prefixes", "next"])
        for s in sites:
            j = site_json(s)
            w.writerow([j["addr"], j["mnemonic"], j["function"], hits.get(s["addr"], 0),
                        " ".join(f"{k}={v}" for k, v in j["prefixes"].items()),
                        "" if s["next"] == [s["addr"] + 4] else " ".join(j["next"] or ["jr"])])
    info["sites"], info["sites_hit"] = len(sites), sum(1 for s in sites if hits.get(s["addr"]))
    (Path(a.out) / "coverage.json").write_text(json.dumps(info, indent=2) + "\n")
    say(f"{info['sites_hit']} of {len(sites)} sites executed; {sum(hits.values())} hits; wall {info['wall_seconds']} s"
        f" -> {dest}")
    if not a.keep_log:
        log.unlink(missing_ok=True)


def coverage_rates(out):
    """Hits per emulated second of every site in coverage.csv (over its window, coverage.json)."""
    info = json.loads((out / "coverage.json").read_text())
    span = (info["end_usec"] - info["armed_usec"]) / 1e6
    rows = list(csv.DictReader(open(out / "coverage.csv")))
    return {int(r["addr"], 16): (int(r["hits"]) / span, r) for r in rows}


def pick_sites(out, how, per_kind, minimum):
    """all: every site the coverage run saw executed; auto: the task 046 sites, then for each mnemonic the most
    executed sites (up to per_kind with at least `minimum` hits). Sites after jr/jalr are left out."""
    rates = coverage_rates(out)
    rows = [r for _, r in rates.values() if r["next"] != "jr" and int(r["hits"]) >= max(1, minimum)]
    if how == "all":
        return sorted(int(r["addr"], 16) for r in rows)
    chosen = {a for a in TASK046_SITES if a in rates}
    by = {}
    for r in rows:
        by.setdefault(r["mnemonic"], []).append(r)
    for rs in by.values():
        rs.sort(key=lambda r: -int(r["hits"]))
        chosen.update(int(r["addr"], 16) for r in rs[:per_kind])
    return sorted(chosen)


def ready_usec(track):
    """The emulated usec of READY on the track's reference route (where ppsspp_race arms its breakpoints)."""
    import ppsspp_ctl as pc
    import scorecard as sc
    return int(pc.vblank_us(sc.pp_routes(track)[1]))


def clock_usec(track, clock):
    """PPSSPP's emulated usec when the player's race clock first reaches `clock` in the scorecard's reference race
    (ref/scorecard/trajectories/<track>.csv)."""
    import scorecard as sc
    with open(sc.REF / "trajectories" / f"{track}.csv") as f:
        next(f)
        for line in f:
            w = line.split(",")
            if int(w[1]) == sc.PLAYER and 0.0 < float(w[2]) and float(w[2]) >= clock:
                return int(w[0])
    sys.exit(f"vfpu_probe: the reference race of {track} never reaches race clock {clock}")


def cmd_sample(a):
    all_sites = {s["addr"]: s for s in scan()}
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    cov = next((d for d in ([Path(a.coverage)] if a.coverage else [out, out.parent])
                if (d / "coverage.csv").exists() and (d / "coverage.json").exists()), None)
    if a.sites in ("auto", "all"):
        if cov is None:
            sys.exit(f"vfpu_probe: no coverage.csv in {out} or {out.parent}: run `cover` first or name the sites")
        addrs = pick_sites(cov, a.sites, a.per_kind, a.min_hits)
    else:
        addrs = [int(x, 16) for x in a.sites.split(",")]
    rates = coverage_rates(cov) if cov else {}
    sites = []
    for x in addrs:
        if x not in all_sites:
            sys.exit(f"vfpu_probe: 0x{x:08X} is not a known site (see `scan`)")
        if all_sites[x]["next"] is None:
            say(f"skipping 0x{x:08X}: delay slot of jr/jalr")
            continue
        sites.append(all_sites[x])
    # One breakpoint an address: its operand part (the site there) and the result parts (the sites that end there).
    plan = {}
    for s in sites:
        plan.setdefault(s["addr"], {"op": None, "res": []})["op"] = s
        for nxt in s["next"]:
            plan.setdefault(nxt, {"op": None, "res": []})["res"].append(s)
    # A hot site logs for a shorter time, from GO on (READY + 200 vblanks, 3.3 s; much of the race's code runs only
    # once the ships move), so that it gives about --cap rows (its rate from the coverage run); the task 046 sites
    # and every site under the cap log from READY for the whole run. A breakpoint serving several sites logs for the
    # longest of their spans.
    full = (a.seconds + 4.0) * 1e6
    go = int(200 * 16683.3)
    if a.span_from:
        # Task 048: a hot site's span starts at this race clock instead of GO (the race clock runs from GO on
        # emulated time, so READY + 200 vblanks + the clock), to sample the stretch before a divergence.
        go += int(a.span_from * 1e6)
    span = {}
    for s_ in sites:
        rate = rates.get(s_["addr"], (0.0, None))[0]
        sp = None
        if a.cap and rate * full / 1e6 > a.cap and s_["addr"] not in TASK046_SITES:
            sp = max(int(a.cap / rate * 1e6), 200000)
        span[s_["addr"]] = sp
    if a.window:
        # Task 048: every site logs every execution between two race clocks (no cap), placed on emulated time by the
        # scorecard's reference race (its player samples carry PPSSPP's usec), so that a divergence's frames are
        # covered whole.
        c0, c1 = (float(x) for x in a.window.split(","))
        u0, u1 = clock_usec(a.track, c0), clock_usec(a.track, c1)
        go = u0 - ready_usec(a.track)
        span = {s_["addr"]: u1 - u0 for s_ in sites}
        say(f"window: race clock {c0} to {c1} s, usec {u0} to {u1}")
    bps = []
    for addr in sorted(plan):
        p = plan[addr]
        regs, spans = [], []
        for s_ in p["res"]:
            regs += s_["d"]
            spans.append(span[s_["addr"]])
        if p["op"]:
            regs += p["op"]["s"] + p["op"]["t"]
            spans.append(span[p["op"]["addr"]])
        fmt = "VP {usec:d} " + " ".join(f"{{{scalar_name(r)}:x}}" for r in regs)
        bps.append((addr, fmt, None if None in spans else (go, max(spans))))
    WORK.mkdir(parents=True, exist_ok=True)
    log = WORK / f"sample_{a.track}_{out.name}.log"
    if a.reuse_log and log.exists():
        old = json.loads((out / "sites.json").read_text()) if (out / "sites.json").exists() else {}
        info = old.get("run", {"track": a.track})
        say(f"reusing {log}")
    else:
        say(f"sampling {len(sites)} sites ({len(bps)} breakpoints) on {a.track} to race clock {a.seconds} s")
        info = ppsspp_race(a.track, log, bps, a.seconds, a.cpu_core)
    rows = {s["addr"]: [] for s in sites}
    pending = None               # (site, usec, operand words) of the line just before
    lines = dropped = 0
    steps = Path(str(log) + ".steps.log")
    src = steps if info.get("stepping") else log
    for line in open(src, errors="replace"):
        m = BKP_RE.search(line)
        if not m or m[2] != "VP":
            continue
        lines += 1
        addr = int(m[1], 16)
        vals = (m[3] or "").split()
        usec, vals = int(vals[0]), [int(v, 16) for v in vals[1:]]
        p = plan.get(addr)
        if p is None:
            pending = None
            continue
        at = 0
        for s in p["res"]:
            n = len(s["d"])
            if pending is not None and pending[0] is s:
                rows[s["addr"]].append((pending[1], pending[2], vals[at:at + n]))
                pending = None
            at += n
        if pending is not None:
            dropped += 1
        pending = None
        if p["op"]:
            s = p["op"]
            n = len(s["s"]) + len(s["t"])
            pending = (s, usec, vals[at:at + n])
    meta = []
    for s in sites:
        j = site_json(s)
        rs = rows[s["addr"]]
        j["rows"] = len(rs)
        j["span_s"] = None if span[s["addr"]] is None else round(span[s["addr"]] / 1e6, 3)
        j["run"] = {"track": a.track, "until_clock": a.seconds, "date": time.strftime("%Y-%m-%d"),
                    **({"window": a.window} if a.window else {})}
        meta.append(j)
        name = f"{s['addr']:08X}.csv"
        with open(out / name, "w", newline="") as f:
            w = csv.writer(f)
            ns, nt = len(s["s"]), len(s["t"])
            w.writerow(["usec"] + [f"s{i}" for i in range(ns)] + [f"t{i}" for i in range(nt)]
                       + [f"d{i}" for i in range(len(s["d"]))])
            for usec, ops, res in rs:
                w.writerow([usec] + [f"{v:08X}" for v in ops] + [f"{v:08X}" for v in res])
        say(f"  {j['addr']} {j['mnemonic']:10} {str(j['function']):24} {len(rs)} rows -> {out / name}")
    info["log_lines"], info["unpaired"] = lines, dropped
    old = json.loads((out / "sites.json").read_text()) if (out / "sites.json").exists() else {}
    keep = {x["addr"]: x for x in old.get("sites", [])}
    keep.update({x["addr"]: x for x in meta})
    (out / "sites.json").write_text(json.dumps({"run": info, "sites": [keep[k] for k in sorted(keep)]}, indent=2)
                                    + "\n")
    say(f"{lines} log lines, {dropped} operand lines without their result; wall {info.get('wall_seconds')} s; "
        f"player {info.get('player_off_reference_m')} m from the reference at {info.get('end_clock')} s")
    if not a.keep_log:
        log.unlink(missing_ok=True)
        steps.unlink(missing_ok=True)


# ------------------------------------------------------------------------------------------- the port's side

HARNESS_HEAD = r"""// Generated by tools/vfpu_probe.py port: the corpus's own code for each sampled site, run on PPSSPP's operands.
#include <psprecomp/allegrex_context.hpp>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <bit>
using psprecomp::AllegrexContext;
static std::size_t idx(unsigned r) { return ((r >> 2) & 7u) * 16u + (r & 3u) * 4u + ((r >> 5) & 3u); }
// The rounding mode of patch 0020 (PURE_VFPU_DOT), where the header has one (a header from before it has none).
template <class C> static void set_dot_mode(unsigned m) { if constexpr (requires { C::vfpu_dot_mode(); }) C::vfpu_dot_mode() = m; }
"""


def snippet(addr, units):
    """The generated statement block of the instruction at addr (between its label and the following goto)."""
    lab = f"L_{addr:08X}:"
    for text in units:
        i = text.find("\n" + lab + "\n")
        if i < 0:
            continue
        body = text[i + len(lab) + 2:]
        j = body.find("\n    goto L_")
        k = body.find("\nL_")
        end = min(x for x in (j, k) if x >= 0)
        return body[:end]
    return None


def cmd_port(a):
    d = Path(a.dir)
    meta = json.loads((d / "sites.json").read_text())["sites"]
    if a.kinds:
        meta = [j for j in meta if j["kind"] in a.kinds.split(",")]
    units = [f.read_text() for f in sorted((ROOT / "generated").glob("generated_unit_*.cpp"))]
    names = {}
    for r in range(128):
        names[scalar_name(r)] = r
    src = [HARNESS_HEAD]
    cases = []
    for j in meta:
        addr = int(j["addr"], 16)
        body = snippet(addr, units)
        if body is None:
            say(f"{j['addr']}: no generated block (delay slot inlined?): skipped")
            continue
        if "goto" in body or "return" in body:
            say(f"{j['addr']}: generated block has control flow: skipped")
            continue
        pf = j["prefixes"]
        fn = f"site_{addr:08X}"
        s_regs = [names[n] for n in j["s"] + j["t"]]
        d_regs = [names[n] for n in j["d"]]
        src.append(f"static void {fn}(AllegrexContext &ctx, const std::uint32_t *in, std::uint32_t *out) {{\n"
                   f"  static const unsigned sr[] = {{{', '.join(map(str, s_regs)) or '0'}}};\n"
                   f"  static const unsigned dr[] = {{{', '.join(map(str, d_regs))}}};\n"
                   f"  for (unsigned i = 0; i < {len(s_regs)}u; ++i) ctx.vfpu[idx(sr[i])] = std::bit_cast<float>(in[i]);\n"
                   f"  ctx.vfpu_ctrl[0] = {int(pf.get('s', '0xE4'), 16)}u; ctx.vfpu_ctrl[1] = {int(pf.get('t', '0xE4'), 16)}u;"
                   f" ctx.vfpu_ctrl[2] = {int(pf.get('d', '0x0'), 16)}u;\n"
                   f"{body}\n"
                   f"  for (unsigned i = 0; i < {len(d_regs)}u; ++i) out[i] = std::bit_cast<std::uint32_t>(ctx.vfpu[idx(dr[i])]);\n"
                   f"}}\n")
        cases.append((j, fn, len(s_regs), len(d_regs)))
    src.append("int main(int argc, char **argv) {\n  if (argc < 4) return 2;\n"
               "  std::uint32_t in[64], out[64]; static AllegrexContext ctx{};\n"
               "  if (const char *m = std::getenv(\"PURE_VFPU_DOT\")) set_dot_mode<AllegrexContext>(std::strcmp(m, \"ppsspp\") == 0 ? 1u : 0u);\n"
               "  FILE *f = std::fopen(argv[2], \"r\"), *g = std::fopen(argv[3], \"w\");\n"
               "  if (!f || !g) return 3;\n  char line[4096];\n  std::fgets(line, sizeof line, f);\n")
    for j, fn, ns, nd in cases:
        src.append(f"  if (!std::strcmp(argv[1], \"{j['addr']}\")) {{\n"
                   f"    std::fprintf(g, \"{','.join(f'd{i}' for i in range(nd))}\\n\");\n"
                   f"    while (std::fgets(line, sizeof line, f)) {{\n"
                   f"      char *p = std::strchr(line, ',');\n"
                   f"      for (int i = 0; i < {ns}; ++i) {{ in[i] = (std::uint32_t)std::strtoul(p + 1, &p, 16); }}\n"
                   f"      {fn}(ctx, in, out);\n"
                   f"      for (int i = 0; i < {nd}; ++i) std::fprintf(g, i ? \",%08X\" : \"%08X\", out[i]);\n"
                   f"      std::fprintf(g, \"\\n\");\n    }}\n    return 0;\n  }}\n")
    src.append("  return 1;\n}\n")
    WORK.mkdir(parents=True, exist_ok=True)
    tag = f"_{a.tag}" if a.tag else ""
    cpp, exe = WORK / f"port_harness{tag}.cpp", WORK / f"port_harness{tag}"
    cpp.write_text("".join(src))
    # The corpus's flags (build/arm64/compile_commands.json for generated_unit_*.cpp): -O2 -std=gnu++20 -arch arm64
    # -ffp-contract=off (patch 0020); --fp-contract on gives the flags of the corpus before patch 0020.
    include = Path(a.include) if a.include else ROOT / "vendor" / "portablekit" / "include"
    cmd = ["/usr/bin/clang++", "-O2", "-std=gnu++20", "-arch", "arm64", f"-ffp-contract={a.fp_contract}",
           f"-I{include}", str(cpp), "-o", str(exe)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit("vfpu_probe: the harness did not compile:\n" + r.stderr[-3000:])
    # Without --modes the rounding mode is the environment's (PURE_VFPU_DOT; the default is the PSP's) and the
    # results go to <ADDR>.port.csv; with --modes each mode's go to <ADDR>.port.<mode>.csv (with --tag:
    # <ADDR>.port.<tag>.<mode>.csv), so that one set holds the port's results under both.
    import os
    runs = [(m, f".port.{a.tag + '.' if a.tag else ''}{m}.csv") for m in a.modes.split(",")] if a.modes \
        else [(os.environ.get("PURE_VFPU_DOT"), f".port{'.' + a.tag if a.tag else ''}.csv")]
    for mode, suffix in runs:
        env = dict(os.environ)
        if mode:
            env["PURE_VFPU_DOT"] = mode
        for j, fn, ns, nd in cases:
            src_csv = d / f"{int(j['addr'], 16):08X}.csv"
            dst = d / f"{int(j['addr'], 16):08X}{suffix}"
            r = subprocess.run([str(exe), j["addr"], str(src_csv), str(dst)], env=env)
            if r.returncode:
                sys.exit(f"vfpu_probe: the harness failed on {j['addr']} ({r.returncode})")
        say(f"{len(cases)} sites under PURE_VFPU_DOT={mode or 'unset'} -> {d}/<ADDR>{suffix}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan", help="list the sites")
    s.add_argument("--kinds", help="comma-separated kinds (vdot,vhdp,vmmul,vtfm,vsin,...)")
    s.set_defaults(fn=cmd_scan)
    for name, fn in (("cover", cmd_cover), ("sample", cmd_sample)):
        s = sub.add_parser(name)
        s.add_argument("--track", default="vineta_k")
        s.add_argument("--seconds", type=float, default=3.0 if name == "cover" else 12.0,
                       help="run until the player's race clock reaches this")
        s.add_argument("--out", default=str(OUT))
        s.add_argument("--keep-log", action="store_true", help="keep PPSSPP's log in out/vfpu_probe/")
        s.add_argument("--reuse-log", action="store_true", help="parse the kept log again instead of running")
        s.add_argument("--cpu-core", type=int, choices=[0, 1, 2, 3],
                       help="PPSSPP's CPU core for the run (default: the ini's, 1 the JIT on this machine)")
        s.set_defaults(fn=fn)
        if name == "cover":
            s.add_argument("--kinds")
        else:
            s.add_argument("--sites", default="all",
                           help="all or auto (from coverage.csv), or ADDR,ADDR,... (hex)")
            s.add_argument("--cap", type=int, default=8000,
                           help="about this many rows a site: hotter sites log for a shorter time (0: no cap)")
            s.add_argument("--per-kind", type=int, default=4, help="auto: sites per mnemonic")
            s.add_argument("--min-hits", type=int, default=50, help="auto: least hits in the coverage run")
            s.add_argument("--coverage", help="the directory with coverage.csv and coverage.json (default: --out, "
                                              "then its parent)")
            s.add_argument("--span-from", type=float, default=0.0,
                           help="a hot site logs from this race clock (s) instead of from GO")
            s.add_argument("--window", help="FROM,TO: every site logs every execution between these race clocks (s)"
                                            " and nothing else (placed by the scorecard's reference race)")
    s = sub.add_parser("port", help="the port's results for the samples")
    s.add_argument("dir", nargs="?", default=str(OUT))
    s.add_argument("--modes", help="ppsspp,psp: run under each rounding mode (PURE_VFPU_DOT), one file each")
    s.add_argument("--kinds", help="only the sites of these kinds")
    s.add_argument("--include", help="another include directory for the harness (header experiments)")
    s.add_argument("--fp-contract", default="off", choices=["off", "on", "fast"],
                   help="clang's -ffp-contract (the corpus: off since patch 0020, on before)")
    s.add_argument("--tag", help="a name for the results (<ADDR>.port.<tag>[.<mode>].csv) and the harness")
    s.set_defaults(fn=cmd_port)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
