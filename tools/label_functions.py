#!/usr/bin/env python3
"""Resolve code-to-string references from the PRX relocations and label functions by the source files they mention.

Inputs:  disc/PSP_GAME/SYSDIR/BOOT.BIN, config/function_map.csv (from Ghidra)
Outputs: out/strings-xrefs.csv   (string_addr, insn_addr, function, string)
         config/function_labels.csv (function_start, function_name, source_files;...)
         out/string-refs-summary.txt
A HI16 relocation followed by LO16 relocation(s) in .rel.text gives the exact address a lui/addiu pair builds,
so no disassembler is needed. Load base 0x08804000.
"""
import csv, re, struct, sys
from bisect import bisect_right

BASE = 0x08804000
elf = open("disc/PSP_GAME/SYSDIR/BOOT.BIN", "rb").read()

def phdrs():
    phoff = struct.unpack_from("<I", elf, 28)[0]; phnum = struct.unpack_from("<H", elf, 44)[0]
    return [struct.unpack_from("<8I", elf, phoff + i * 32) for i in range(phnum)]
PH = phdrs()                      # (type, off, vaddr, paddr, filesz, memsz, flags, align)
def file_off(vaddr):
    for pt, off, va, pa, fsz, msz, fl, al in PH:
        if va <= vaddr < va + fsz: return off + vaddr - va
    return None
def sections():
    shoff = struct.unpack_from("<I", elf, 32)[0]; shnum, shstrndx = struct.unpack_from("<HH", elf, 48)
    sho, ssz = struct.unpack_from("<II", elf, shoff + shstrndx * 40 + 16); strs = elf[sho:sho + ssz]
    out = {}
    for i in range(shnum):
        nm, ty, fl, ad, of, sz, lk, inf, al, es = struct.unpack_from("<10I", elf, shoff + i * 40)
        out[strs[nm:strs.find(b"\0", nm)].decode()] = dict(type=ty, addr=ad, off=of, size=sz, info=inf)
    return out
S = sections()

# strings: NUL-terminated printable runs in .rodata and .data, keyed by vaddr
strings = {}
for sec in (".rodata", ".data"):
    s = S[sec]; blob = elf[s["off"]:s["off"] + s["size"]]
    for m in re.finditer(rb"[\x20-\x7e]{4,300}\0", blob):
        strings[s["addr"] + m.start()] = m.group(0)[:-1].decode()

# relocations: HI16 paired with following LO16(s)
R_MIPS_32, R_MIPS_26, R_MIPS_HI16, R_MIPS_LO16 = 2, 4, 5, 6
rel = S[".rel.text"]
def insn(vaddr):
    return struct.unpack_from("<I", elf, file_off(vaddr))[0]
refs = []            # (insn_vaddr, target_vaddr, kind)
pending_hi = []
for i in range(rel["size"] // 8):
    r_off, r_info = struct.unpack_from("<II", elf, rel["off"] + i * 8)
    rtype = r_info & 0xFF; ofs_base = (r_info >> 8) & 0xFF; addr_base = (r_info >> 16) & 0xFF
    insn_va = PH[ofs_base][2] + r_off
    tgt_base = PH[addr_base][2]
    w = insn(insn_va)
    if rtype == R_MIPS_HI16:
        pending_hi.append((insn_va, (w & 0xFFFF) << 16))
    elif rtype == R_MIPS_LO16:
        lo = w & 0xFFFF
        if lo >= 0x8000: lo -= 0x10000
        for hi_va, hi in pending_hi:
            refs.append((hi_va, (hi + lo + tgt_base) & 0xFFFFFFFF, "hi16"))
        refs.append((insn_va, ((pending_hi[-1][1] if pending_hi else 0) + lo + tgt_base) & 0xFFFFFFFF, "lo16"))
        pending_hi = []
    elif rtype == R_MIPS_32:
        refs.append((insn_va, (w + tgt_base) & 0xFFFFFFFF, "word"))
    elif rtype == R_MIPS_26:
        refs.append((insn_va, (((w & 0x03FFFFFF) << 2) + tgt_base) & 0xFFFFFFFF, "j26"))

# functions
funcs = []
with open("config/function_map.csv") as f:
    for row in csv.DictReader(f):
        funcs.append((int(row["start"], 16), int(row["end"], 16), row["name"]))
funcs.sort(); starts = [s for s, e, n in funcs]
def func_of(va):
    i = bisect_right(starts, va) - 1
    if i >= 0 and funcs[i][0] <= va <= funcs[i][1]: return funcs[i]
    return None

xrefs = []; by_func = {}
for insn_va, tgt, kind in refs:
    if kind not in ("hi16", "lo16"): continue
    if tgt not in strings: continue
    text = strings[tgt]; fn = func_of(insn_va + BASE)
    xrefs.append((tgt + BASE, insn_va + BASE, fn[2] if fn else "", text))
    if fn and ("/Work/" in text or text.endswith((".cpp", ".h", ".c"))):
        base = text.replace("\\", "/").rsplit("/", 1)[-1]
        by_func.setdefault(fn, set()).add(base)

xrefs.sort(key=lambda r: (r[0], r[1]))
seen = set(); rows = []
for r in xrefs:
    if (r[0], r[1]) in seen: continue
    seen.add((r[0], r[1])); rows.append(r)
with open("out/strings-xrefs.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n"); w.writerow(["string_addr", "insn_addr", "function", "string"])
    for a, b, fn, t in rows: w.writerow([f"0x{a:08X}", f"0x{b:08X}", fn, t])
with open("config/function_labels.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n"); w.writerow(["function_start", "function_name", "source_files"])
    for fn in sorted(by_func): w.writerow([f"0x{fn[0]:08X}", fn[2], ";".join(sorted(by_func[fn]))])
nrel = rel["size"] // 8
summary = [f"relocations {nrel}, resolved refs {len(refs)}, string refs {len(rows)}, strings {len(strings)}",
           f"functions {len(funcs)}, functions referencing a source path {len(by_func)}",
           f"distinct source files referenced {len(set(x for v in by_func.values() for x in v))}"]
open("out/string-refs-summary.txt", "w").write("\n".join(summary) + "\n"); print("\n".join(summary))
# show how the interesting strings are reached
for key in ("host0:", "umd:", "Log.txt", "TrackStartup", "%s", "DevMenu"):
    hits = [r for r in rows if key in r[3]]
    print(f"  {key!r}: {len(hits)} refs, e.g.", [(f'0x{b:08X}', fn, t[:40]) for a, b, fn, t in hits[:3]])

# ---- import callers: every jal (R_MIPS_26) whose target is an import stub
stubs = {}
with open("config/imports.csv") as f:
    for row in csv.DictReader(f):
        stubs[int(row["stub_abs"], 16)] = (row["library"], row["name"])
callers = {}
for insn_va, tgt, kind in refs:
    if kind != "j26": continue
    t = tgt + BASE
    if t in stubs:
        fn = func_of(insn_va + BASE)
        callers.setdefault(t, []).append((insn_va + BASE, fn[2] if fn else "?"))
with open("out/import-callers.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n"); w.writerow(["library", "import", "call_count", "callers"])
    for t, (lib, name) in sorted(stubs.items(), key=lambda kv: (kv[1][0], kv[1][1])):
        cs = callers.get(t, [])
        w.writerow([lib, name, len(cs), ";".join(f"{fn}@0x{a:08X}" for a, fn in cs)])
uncalled = [stubs[t][1] for t in stubs if t not in callers]
print(f"import stubs {len(stubs)}, called by jal {len(callers)}, never called directly {len(uncalled)} (reached via pointers or unused)")
for name in ("sceDisplayWaitVblankStart", "sceDisplayWaitVblankStartCB", "sceDisplayGetVcount", "sceDisplaySetFrameBuf", "sceIoWrite", "sceKernelDelayThread", "sceGeListEnQueue", "sceGeListSync", "sceGeDrawSync", "sceCtrlReadBufferPositive", "sceCtrlPeekBufferPositive", "sceKernelStdout", "sceKernelPrintf", "sceAudioOutputPannedBlocking"):
    for t, (lib, n) in stubs.items():
        if n == name:
            cs = callers.get(t, [])
            print(f"  {name}: {len(cs)} calls", sorted(set(fn for a, fn in cs))[:8])
