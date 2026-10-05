# Codegen baseline: BOOT.BIN on PortableKit 8b0c3fe

Spike S4 report (2026-10-05). The commands are the basis of `tools/regen.sh`.


Date: 2026-10-05. Vendor: **PortableKit 8b0c3fe** (the S3 recommendation). Yakumo 962d38b was run the same way for
comparison.

Machine: Apple M4 Pro, 12 cores, 24 GB. Toolchain: Apple clang 17.0.0 (`/usr/bin/clang++`), cmake 4.4.4 and
ninja 1.13.2 from `/opt/homebrew/bin`, arm64.

Input: `~/dev/pure-recomp/disc/PSP_GAME/SYSDIR/BOOT.BIN`.

- SHA-256 `9033e4dd3433116eee2fd309f9c775e332e54da292d7a85075d3b4ccdb9b5750`, the same before and after the run
  (read-only).
- e_type 0xFFA0, which the framework reports as `is_psp_prx: true`. Module `WO_Game` v1.1.

"Inferred" marks anything not measured.

## 5. Build of the framework tools

Commands (scriptable):

```zsh
source ~/dev/pure-recomp/tools/env.sh
PK=~/dev/scratch/PortableKit
/opt/homebrew/bin/cmake -S $PK -B $PK/build-tools -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
  -DCMAKE_MAKE_PROGRAM=/opt/homebrew/bin/ninja -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DPSPRECOMP_CCACHE=OFF
/opt/homebrew/bin/cmake --build $PK/build-tools --target psp_analyze psp_recomp dump_function -j 12
```

Notes on the flags:

- `-DPSPRECOMP_CCACHE=OFF` serves two purposes. env.sh points `CCACHE_DIR` into `~/dev/pure-recomp/.ccache`,
  which this spike must not write. Turning ccache off also gives cold timings.
- The project enables only CXX, so CMake warns that `CMAKE_C_COMPILER` is unused. That is harmless.
- CMake also warns that Ninja 1.13.2 cannot recover a damaged `.ninja_deps` (cmake/BuildLock.cmake:38). The fix is
  to build only through `cmake --build`.

Wall times (cold, no ccache):

| Step | PortableKit | Yakumo (same flags, `~/dev/scratch/Yakumo/build-tools`) |
|---|---|---|
| Configure | 2 s | 2 s |
| `psp_analyze` + `psp_recomp` + `dump_function` (16 steps) | 2.87 s wall (11.6 s user), re-timed after `--target clean` | 3 s |
| Everything incl. tests (235 steps), PortableKit only | 28 s | n/a |
| `ctest`, PortableKit only | 20/20 passed, 14 s | n/a |

Logs: `~/dev/scratch/logs/build_pk.log`, `build_yk.log`.

## 6. Analyzer and recompiler on BOOT.BIN

Commands:

```zsh
ELF=~/dev/pure-recomp/disc/PSP_GAME/SYSDIR/BOOT.BIN
mkdir -p ~/dev/scratch/analyze-wipeout-pk
$PK/build-tools/psp_analyze $ELF ~/dev/scratch/analyze-wipeout-pk/report.json 0x08804000
mkdir -p ~/dev/scratch/gen-wipeout
/usr/bin/time -l $PK/build-tools/psp_recomp $ELF --auto ~/dev/scratch/gen-wipeout 0x08804000 \
  > ~/dev/scratch/logs/gen_pk.stdout 2> ~/dev/scratch/logs/gen_pk.stderr
```

`0x08804000` is also both tools' default (include/psprecomp/elf32.hpp:15), so passing it changes nothing. The unit
span is left at its default of 0x4000 (tools/codegen_main.cpp:1850-1852).

### Analyzer (`report.json`, 0.22 s)

| Item | Value |
|---|---|
| Guest RAM required | 32 MiB |
| Runtime entry | 0x0880B238 (relative 0x00007238) |
| Segments | 0x08804000 filesz 2883248 (r-x); 0x08AC3EB0 filesz 14956, memsz 732932 (rw-) |
| Executable ranges | 34: `.text` 0x08804000-0x08A42A44 (2,353,732 bytes), plus 33 stub ranges up to 0x08A432F4 |
| Relocations | 111698: R_MIPS_32 19983, R_MIPS_26 47251, HI16 20271, LO16 24193. 0 unsupported, 0 invalid |
| Module | WO_Game v1.1. Module info at 0x08A435A8; `gp` reported as 0x00000000; stubs 0x08A43310-0x08A435A4 |
| Imports | 278 in 33 libraries. 24 NIDs have no name in configs/nids.csv: sceHttp 10, ThreadManForUser 7, sceRtc 2, and one each for sceParseUri, sceParseHttp, sceNetAdhoc, ModuleMgrForUser, LoadExecForUser |
| Function seeds | **10962**: `direct_jal_target` 6668, `relocated_r_mips32_code_pointer` 3577, `materialized_code_pointer` 380, `relocated_data_code_pointer` 336, `elf_entry` 1 |
| Functions | 10962, none truncated |
| Unique instructions (reachable labels) | **456243** |
| Instructions summed per function (with overlap) | 605434 |
| Unique basic-block entries | 121928 (163516 with overlap; 41588 overlapping labels) |
| Indirect call sites | 1358 |
| Unsupported instruction occurrences | 0 |

Yakumo's analyzer gives the same figures, and its function-seed CSV is byte-identical after sorting.

### Recompiler (`--auto`)

| Item | PortableKit | Yakumo |
|---|---|---|
| Exit code | 0 | 0 |
| Wall time | **84.7 s** (82.0 s user, single-threaded). Peak RSS 216 MB | 86 s |
| Function seeds / emitted instructions | 10962 / 456243 | same |
| Registered block entries (every word of the executable ranges) | 588989 | same |
| Translation units | **144** `generated_unit_0000..0143.cpp` (16 KiB of guest code each), plus `generated_registry.cpp` (162 KB, 278 import wrappers) and `recomp_units.hpp` (22 KB) | 144 |
| Generated size | **154,685,551 bytes** of units (min 835 KB, max 1.38 MB, avg 1.07 MB; 3,412,507 lines). 148 MB on disk | 154,680,643 bytes |

Output layout: `~/dev/scratch/gen-wipeout/` (PortableKit) and `~/dev/scratch/gen-wipeout-yakumo/`. Each holds
`auto_codegen_report.json`.

#### Compile probe (beyond the brief; no runtime was built)

- Command: `clang++ -std=c++20 -arch arm64 -O2 -g0 -c generated_unit_0022.cpp` against PortableKit `include/`.
- This is the largest unit, 1.38 MB, at the flags `portablekit_add_game` uses (cmake/PortableKit.cmake:279).
- Result: **60 s wall, maximum RSS 1.0 GB**.
- Estimate for the whole corpus, inferred: about 6,500-7,000 CPU-seconds. That is roughly 18-20 min at the default
  6 parallel jobs (24 GiB / 4 GiB) and about 10 min at 12 jobs.

### What the corpus emits that is not native code

Search patterns, run over `generated_unit_*.cpp`:

```zsh
grep -ho 'unsupported(0x[0-9A-Fa-f]*u, 0x[0-9A-Fa-f]*u, "[^"]*"' generated_unit_*.cpp \
  | sed 's/.*"\(.*\)"/\1/' | sort | uniq -c | sort -rn          # per reason
grep -c 'not lowered' generated_unit_*.cpp                     # generic/unsupported decodes
grep -ho 'rt\.[a-z_]*(' generated_unit_*.cpp | sort | uniq -c   # runtime calls
grep -ho 'ctx\.execute_vfpu_[a-z_0-9]*(' generated_unit_*.cpp | sort | uniq -c
```

PortableKit corpus. It has **no** "not lowered yet" sites and no "control flow in delay slot" sites. The complete
list:

| Emitted as | Instruction | Words in `.text` (reachable) | Sites |
|---|---|---|---|
| `rt.unsupported(..., "guest break trap")` | `break` code 7 (word 0x000001CD, the GCC divide-by-zero trap) | 121 | 242 |
| `rt.unsupported(..., "guest break trap")` | `break` code 0 (0x0000000D) | 2 | 2 |
| (`break` words in total) | | 123 (2 reachable) | 244 |
| `rt.execute_extra_instruction` (UNVERIFIED helper, shared with the interpreter) | `lvl.q` | 37 (3) | 37 |
| `rt.execute_extra_instruction` | `lvr.q` | 37 (3) | 37 |
| `rt.unsupported(ctx.pc, 0u, "invalid internal function entry")` | none: one dispatcher guard per unit | | 144 |

Notes on these sites:

- Break sites outnumber break words because a word can be emitted in more than one block.
- `execute_extra_instruction` (src/extra_instructions.cpp) prints `[instruction] first use of ...: UNVERIFIED` the
  first time each one runs.

VFPU helper calls are lowered through `AllegrexContext` helpers, not through a fallback:

| Helper | Calls |
|---|---|
| `execute_vfpu_cross_quat` | 108 |
| `execute_vfpu_horizontal` | 61 |
| `execute_vfpu_vminmax` | 27 |
| `execute_vfpu_vrot` | 24 |
| `execute_vfpu_vmmov` | 24 |
| `execute_vfpu_vmscl` | 4 |
| `execute_vfpu_matrix_init` | 4 |
| `execute_vfpu_vocp` | 2 |

Most VFPU code is inlined after `lower_constant_vfpu_accesses` (`*_ct<...>` templates).

Yakumo corpus, for comparison:

| Reason | Sites | What it is |
|---|---|---|
| `guest break trap` | 244 | as above |
| `vfpu not lowered yet` | 74 | `lvl.q` / `lvr.q`: opcode 0x35, words 0xD4xxxxxx; 6 reachable |
| `vfpu4 not lowered yet` | 2 | `vbfy1` (0xD0421EDE at 0x08823774 and 0x08823808; both reachable). PortableKit inlines these (gen-wipeout/generated_unit_0007.cpp, `L_08823774`) |

There are fewer than 30 categories in either corpus, so the tables above are the complete lists.

VFPU mix of BOOT.BIN by mnemonic, from PortableKit's decoder (`~/dev/scratch/tools/vfpuhist_pk.txt`). The file has
25198 VFPU words, 22952 of them reachable. The leading mnemonics, as words (reachable):

| Mnemonic | Words (reachable) |
|---|---|
| sv.q | 7299 (6711) |
| vmov | 5590 (5188) |
| lv.q | 5558 (5055) |
| mtv | 1773 (1608) |
| mfv | 1637 (1451) |
| vscl | 603 |
| vdot | 404 |
| vadd | 374 |
| vsub | 327 |
| vpfxs | 165 |
| vmul | 156 |
| vrsq | 121 |
| vzero | 120 |
| sv.s | 117 |
| vflush | 111 |
| vcrsp/vqmul | 108 |
| lv.s | 88 |
| vsqrt | 87 |
| vfad | 61 |
| vpfxt | 61 |
| vneg | 61 |
| vtfm | 41 |
| lvl.q | 37 |
| lvr.q | 37 |
| viim.s | 35 |
| vmmul | 29 |
| vrcp | 25 |
| vrot | 24 (0) |
| vabs | 21 |
| vone | 18 |
| vidt | 18 (0) |

A per-word classifier over every executable word (`~/dev/scratch/tools/opclass.cpp`, linked against each
framework's `psprecomp_core` objects) confirms these counts.

- PortableKit: zero words decode to `Unsupported` or to the generic `Vfpu` kind. 74 decode to `Extra`
  (lvl.q/lvr.q) and 123 to `Break`.
- Yakumo: 74 decode to `Vfpu` "vfpu" and 2 to `Vfpu` "vfpu4".

### VFPU encodings the decoder treats as the generic `Vfpu` kind

In PortableKit src/decoder.cpp, anything of kind `Vfpu`, `Unsupported` or `Syscall` that reaches codegen becomes
`rt.unsupported(pc, word, "<mnemonic> not lowered yet")` (tools/codegen_main.cpp:1254-1259). The `default:` arm of
`emit_regular` does the same (:884-886). Words matching the `Extra` table (src/extra_instructions.cpp:44-86) are
caught before the opcode switch (decoder.cpp:51-55) and never reach these arms:

- ll, sc
- lvl.q, lvr.q, svl.q, svr.q
- vsbn, vdet, vwbn
- vrnds, vsbz, vlgb, vi2c, vi2us
- vsrt1-4, vbfy2
- vmfvc, vmtvc, vt4444, vt5551

Generic `Vfpu` returns in PortableKit, with the Yakumo equivalent:

| Mnemonic | Encoding | PortableKit decoder.cpp | Yakumo decoder.cpp |
|---|---|---|---|
| `cop2/vfpu` | op 0x12 with rs not 3 (mfv), 7 (mtv) or 8 (bv*) | :217 | :554 |
| `vfpu0` | op 0x18 with op field 3-6. Field 2 (vsbn) is Extra in PortableKit and generic in Yakumo | :242 | :629 |
| `vfpu1` | op 0x19 with field 3, field 5 when not a triple, or field 7. Field 6 (vdet) is Extra in PortableKit; Yakumo also leaves 5 (vcrs.t) and 6 generic | :267 | :649 |
| `vfpu3` | op 0x1B with field 1 or 4 | :284 | :666 |
| `vfpu` | op 0x35 / 0x3D (lvl/lvr/svl/svr.q) | :291, unreachable because Extra catches all of them | :673, **reached 74 times on BOOT.BIN** |
| `vfpu4` | op 0x34, group 0, unlisted op (8-15, 25, 27, 29-31) | :393 | :817 |
| `vfpu4` | op 0x34, any other unlisted group/op | :396 | :822 |
| `vfpu-matrix1` | op 0x3C group 28, matrix op not 0, 3, 6 or 7 | :433 | :859 |
| `vfpu6` | op 0x3C groups 24-27, 30, 31 | :440 | :866 |

Op 0x34 instructions Yakumo leaves as `vfpu4` but PortableKit lowers (decoder.cpp:324-366):

- vrndi, vrndf1, vrndf2
- vi2uc, vi2s
- vt5650
- vbfy1

## 7. Refusal check

**The recompiler did not refuse the ELF.** Neither tool needed a config file, a TOML or a different e_type.

- How the framework handles a relocatable PRX (e_type 0xFFA0, `kElfTypePspPrx`, elf32.hpp:14):
  - `load_and_relocate` applies the relocations (PortableKit src/elf32.cpp:223; Yakumo :246).
  - `runtime_entry()` adds the load base (PortableKit :162; Yakumo :173).
  - Seeds come from relocations. The section scan for data code pointers runs only for non-PRX executables
    (PortableKit src/program_analysis.cpp:369; Yakumo :378).
- What the MHP3rd profile does differently (Yakumo):
  - It feeds `profiles/mhp3rd/game/EBOOT.ELF`, an EBOOT decrypted by its installer
    (scripts/generate.sh:13-26). Our disc already ships the decrypted `BOOT.BIN`.
  - It passes no load base, so the default 0x08804000 applies (the same as ours).
  - It uses 64 MiB guest RAM (host/mhp3rd_profile.hpp:13). Wipeout needs 32 MiB.
  - It adds 355 overlay corpora with `--prefix`. `config/mhp3rd_npjb40001.toml` is not read by any code.
- Inferred: the MHP3rd EBOOT.ELF is also a 0xFFA0 PRX, because its profile uses relative addresses with
  `kLoadBase`. It was not checked against a file.
- For a later runtime build on PortableKit, the profile needs:
  - `load_base = 0x08804000` and `guest_ram_bytes = 32 MiB`.
  - `executable_sha256 = 9033e4dd...`, so that the corpus is linked rather than ignored (host/main.cpp:364-388).
  - A game directory holding `EBOOT.ELF` (a copy of BOOT.BIN), `disc.iso` and `ms0/` (host/main.cpp:149, `<PREFIX>_GAME_DIR`).

  The installer's decryption fields can stay empty, as the stand-in profile shows. The headless interpreter run in
  S3 used exactly that layout.

## Blockers and open points

- None blocks codegen. The open points:
  1. The 6 reachable `lvl.q`/`lvr.q` (UNVERIFIED in PortableKit) need a check when first hit.
  2. 32 imports remain without HLE even with FFmpeg (S3 section 4).
  3. The full-corpus compile time has not been measured (estimate above).
  4. The bundled FFmpeg download and build were not exercised.

Scratch artefacts:

| Path | Contents |
|---|---|
| `~/dev/scratch/gen-wipeout/` | PortableKit corpus |
| `~/dev/scratch/gen-wipeout-yakumo/` | Yakumo corpus |
| `~/dev/scratch/analyze-wipeout-{pk,yk}/` | analyzer reports |
| `~/dev/scratch/tools/` | opclass and vfpuhist sources, binaries and outputs |
| `~/dev/scratch/unit-compile-probe/` | the probe object and its log |
| `~/dev/scratch/logs/` | all build and run logs |
