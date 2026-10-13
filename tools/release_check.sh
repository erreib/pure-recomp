#!/bin/bash
# tools/release_check.sh [--history] [--archive ZIP ...]   nothing of the game, no key, no secret goes public (task 087)
#
# Run before the repository or a release archive goes public (docs/release.md, "Publishing"). Prints each finding as
# FILE:LINE: what (or a path), the notes, a summary table and `release_check: PASS` or `FAIL`; exits 0 only on PASS.
# Python's standard library and git only, so it runs in the rig's Git Bash too. About 1 s; --history about 5 s more.
# A value that looks like a key or token is printed by its first digits only.
#
# The tree is HEAD's (`git ls-tree -r HEAD`: what a push publishes; uncommitted changes are not read, which is said):
#   paths     no file under the git-ignored game, vendor, build and scratch paths: disc/ game/ generated/
#             generated-variants/ overlays/ vendor/ ref/ (but ref/README.md) .claude/worktrees/ at the top, build/
#             out/ dist/ ghidra_project/ .ccache/ .venv/ anywhere, no picture at the top (/*.png, /*.bmp)
#   names     no path part with a game-data extension (.iso .cso .bin .wad .at3 .pmf .prx .elf .ovl .pbp .sfo .ppst
#             .ppdmp .gerec) or named like the game's files (packaging/release.env's RELEASE_GAME_NAMES and eboot*
#             umd_data* param.sfo pi.wad icon0.png pic1.png data.bin ms0 savedata psp_game), in any case
#   size      no file over 1 MiB, 1048576 bytes (the function map is 318 KB, the largest patch 215 KB)
#   binaries  every file is text (no NUL in its first 8000 bytes, git's rule) but packaging/icon.png,
#             packaging/macos/Wipeout Pure.icns and packaging/windows/pure.ico
#   keys      no run of 32 or more hex digits (16 bytes: a download pack's XTEA key or an AES key; the packs' RSA
#             modulus is 512 digits) and no 16-byte array literal ({ or [ around 16 0xNN bytes or 4 0xNNNNNNNN words;
#             16 \xNN escapes in a row), unless the allow list of hashes takes it:
#               - 64 digits (a SHA-256) with SHA-256, sha256 or shasum on its line or the two before it, or in the
#                 header of its Markdown table (ref/README.md's captures, the pinned sources in
#                 packaging/THIRD_PARTY_NOTICES.md, the executable's hashes in src/profile/pure_profile.cpp, docs
#                 citing a sum);
#               - 40 digits (a git object id) with commit, tree, PIN or SHA-1 on its line or the two before it, or a
#                 commit of this repository (the PortableKit and tiny-AES-c pins, tools/vendor_setup.sh's PIN);
#               - in config/*.csv, a field of a column whose header names a hash or sha (none today);
#               - vendor/PIN (git-ignored, so only if a commit ever held it).
#   tokens    no GitHub (ghp_ gho_ ghu_ ghs_ ghr_ github_pat_), GitLab (glpat-) or AWS (AKIA) token, no PEM block, no private host name
#   home      no home directory (/Users/NAME, /home/NAME, X:\Users\NAME or X:/Users/NAME, /x/Users/NAME) and no path
#             in the rig's user folder (H:\errei, H:/errei, /h/errei: tools/bundle_windows.sh's machine check), except
#             as notes: in the record (docs/tasks/, docs/history/, docs/research.md: a task's machine paths are
#             history) and in the machine checks' own patterns (this file, tools/bundle_windows.sh, docs/release.md)
# --history adds every commit (`git log --all`, the stash left out: it is this machine's and never pushed):
#   history   the paths and names rules on every path ever added (git log --all --no-renames --diff-filter=A
#             --name-only -m); the keys and tokens rules on every file version ever committed (git rev-list --objects
#             --all), with no binary but the known three and no game file by its header (below)
# --archive ZIP (repeatable, or several after one --archive; out/release-macos/dist/pure-recomp-*.zip,
# out/release-windows/dist/pure-recomp-*.zip):
#   archive   no entry with a game-data path part (the names rule); no entry is a disc image (CD001 at 32769), a PSP
#             executable (a MIPS ELF), an encrypted module (~PSP), a PBP or a PARAM.SFO by its header; BUILDINFO.txt
#             (in the zip, else beside it) is for this zip's version and names a commit of this repository, built
#             clean (no -dirty), and a version without a commit (0.1.0) has its tag v0.1.0 on that commit; for the
#             macOS zip, no entry of the app's Contents/Resources has a game data path part (disc game generated ms0
#             savedata psp_game textures ref) and no text file there holds UCUS98612, PSP_GAME, EBOOT, BOOT.BIN,
#             .iso, .wad or a home path
set -u
cd "$(dirname "$0")/.."
exec python3 - "$@" <<'PY'
import bisect, fnmatch, os, re, subprocess, sys, time, zipfile

T0 = time.time()
LIMIT = 1 << 20
KNOWN_BINARIES = ("packaging/icon.png", "packaging/macos/Wipeout Pure.icns", "packaging/windows/pure.ico")
# .gitignore's paths and what each holds: at the top, and (unanchored there) anywhere.
TOP_IGNORED = {"disc": "the extracted disc", "game": "the runtime's game directory", "generated": "the corpus",
               "generated-variants": "corpus variants", "overlays": "overlay builds", "vendor": "the vendored framework",
               "ref": "the PPSSPP captures", ".claude/worktrees": "agent worktrees"}
ANY_IGNORED = {"build": "build output", "out": "logs and scratch", "dist": "archives", "ghidra_project": "Ghidra's project",
               ".ccache": "the compiler cache", ".venv": "a Python environment"}
GAME_EXTS = (".iso", ".cso", ".bin", ".wad", ".at3", ".pmf", ".prx", ".elf", ".ovl", ".pbp", ".sfo", ".ppst",
             ".ppdmp", ".gerec")
PACKER_NAMES = ("eboot*", "umd_data*", "param.sfo", "pi.wad", "icon0.png", "pic1.png", "data.bin", "ms0", "savedata",
                "psp_game")
RESOURCE_DATA_PARTS = ("disc", "game", "generated", "ms0", "savedata", "psp_game", "textures", "ref")
RESOURCE_STRINGS = ("UCUS98612", "PSP_GAME", "EBOOT", "BOOT.BIN", ".iso", ".wad")
NOTE_PREFIXES = ("docs/tasks/", "docs/history/")
NOTE_FILES = ("docs/research.md",)
CHECKER_FILES = ("tools/release_check.sh", "tools/bundle_windows.sh", "docs/release.md")

HEX_RUN = re.compile(r"(?<![0-9A-Fa-f])[0-9A-Fa-f]{32,}(?![0-9A-Fa-f])")
BYTES16 = re.compile(r"[{\[]\s*(?:0x[0-9A-Fa-f]{1,2}\s*,\s*){15}0x[0-9A-Fa-f]{1,2}\s*,?\s*[}\]]")
WORDS4 = re.compile(r"[{\[]\s*(?:0x[0-9A-Fa-f]{8}[uUlL]*\s*,\s*){3}0x[0-9A-Fa-f]{8}[uUlL]*\s*,?\s*[}\]]")
ESC16 = re.compile(r"(?:\\x[0-9A-Fa-f]{2}){16}")
TOKEN = re.compile(r"(?<![A-Za-z0-9_])(?:gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}|glpat-[A-Za-z0-9_-]{20,}"
                   r"|AKIA[0-9A-Z]{16})|-----BEGIN [A-Z0-9 ]+-----|eriksmedia\.com")  # the last: a private host of Erik's
SHA256_WORD = re.compile(r"sha-?256|shasum", re.I)
OBJECT_WORD = re.compile(r"\b(?:commit|tree|pin|sha-?1)\b", re.I)
HOME = re.compile(r"(?<![\w.:/~-])/Users/(?!Shared\b)[A-Za-z0-9._-]+"
                  r"|(?<![\w.:/~-])/home/[A-Za-z0-9._-]+"
                  r"|(?<![\w])[A-Za-z]:[\\/]{1,2}Users[\\/]{1,2}[A-Za-z0-9._-]+"
                  r"|(?<![\w.:/~-])/[A-Za-z]/Users/[A-Za-z0-9._-]+"
                  r"|(?<![\w])[Hh]:[\\/]{1,2}errei(?![\w.-])"
                  r"|(?<![\w.:/~-])/h/errei(?![\w.-])")


def usage():
    print("usage: tools/release_check.sh [--history] [--archive ZIP ...]")
    sys.exit(2)


def git(*args, data=None):
    """git's stdout (bytes); exits with its stderr when it fails."""
    r = subprocess.run(["git", "-c", "core.quotepath=off", *args], input=data, capture_output=True)
    if r.returncode:
        sys.exit(f"release_check: git {' '.join(args[:3])} failed: {r.stderr.decode(errors='replace').strip()}")
    return r.stdout


def read_blobs(oids):
    """{object id: bytes} for the blobs named, through one `git cat-file --batch`."""
    out = git("cat-file", "--batch", data=("\n".join(oids) + "\n").encode()) if oids else b""
    blobs, i = {}, 0
    while i < len(out):
        nl = out.index(b"\n", i)
        head = out[i:nl].split()
        if len(head) < 3:
            i = nl + 1
            continue
        size = int(head[2])
        blobs[head[0].decode()] = out[nl + 1:nl + 1 + size]
        i = nl + 1 + size + 1
    return blobs


def release_env():
    env = {}
    with open("packaging/release.env", encoding="utf-8") as f:
        for line in f:
            m = re.match(r'([A-Z_]+)=(?:"([^"]*)"|(\S*))', line)
            if m:
                env[m.group(1)] = m.group(2) if m.group(2) is not None else m.group(3)
    return env


ENV = release_env()
GAME_NAMES = tuple(ENV.get("RELEASE_GAME_NAMES", "").split()) + PACKER_NAMES
SLUG = ENV.get("RELEASE_SLUG", "pure-recomp")


def name_problem(path):
    """Why a path part names game data (an extension or a game file's name), or None."""
    for part in path.strip("/").split("/"):
        low = part.lower()
        for ext in GAME_EXTS:
            if low.endswith(ext):
                return f"'{part}' has a game-data extension ({ext})"
        for glob in GAME_NAMES:
            if fnmatch.fnmatchcase(low, glob):
                return f"'{part}' is named like the game's files ({glob})"
    return None


def path_problem(path):
    """Why a tracked path is one of the git-ignored ones, or None."""
    if path == "ref/README.md":
        return None
    for top, what in TOP_IGNORED.items():
        if path == top or path.startswith(top + "/"):
            return f"under {top}/, which .gitignore keeps out ({what})"
    parts = path.split("/")[:-1]
    for name, what in ANY_IGNORED.items():
        if name in parts:
            return f"under a {name}/ directory, which .gitignore keeps out ({what})"
    if "/" not in path and path.lower().endswith((".png", ".bmp")):
        return "a picture at the top, which .gitignore keeps out (/*.png, /*.bmp: captures)"
    return None


def game_header(head):
    """What a file is by its first bytes when it is game data, or None (the packer's and bundle.sh's rules)."""
    if head[:4] == b"\x7fELF" and head[18:20] == b"\x08\x00":
        return "a PSP executable (MIPS ELF)"
    if head[:4] == b"\0PBP":
        return "a PBP"
    if head[:4] == b"~PSP":
        return "an encrypted PSP module"
    if head[:4] == b"\0PSF":
        return "a PARAM.SFO"
    if head[32769:32774] == b"CD001":
        return "a disc image (CD001 at 32769)"
    return None


def is_binary(data):
    return b"\0" in data[:8000]


def short(value):
    return value[:8] + "..." if len(value) > 8 else value


class Keys:
    """The keys and tokens rules on one file's text: findings (line, what) and what the allow list took."""

    def __init__(self, commits):
        self.commits = commits      # 40-digit runs that are commits of this repository (filled by the caller)
        self.allowed = {}           # allow-list reason -> count

    def allow(self, why):
        self.allowed[why] = self.allowed.get(why, 0) + 1

    def scan(self, path, text):
        lines = text.split("\n")
        starts = [0]
        for line in lines[:-1]:
            starts.append(starts[-1] + len(line) + 1)
        findings = []

        def lineno(pos):
            return bisect.bisect_right(starts, pos)

        csv_hash_cols = None
        if fnmatch.fnmatchcase(path, "config/*.csv"):
            header = next((ln for ln in lines if ln and not ln.startswith("#")), "")
            csv_hash_cols = {i for i, col in enumerate(header.split(",")) if re.search(r"hash|sha", col, re.I)}
        for m in HEX_RUN.finditer(text):
            run, n = m.group(0), lineno(m.start())
            if len(set(run.lower())) == 1:
                self.allow("one digit repeated (padding, no key)")
                continue
            context = "\n".join(lines[max(0, n - 3):n])
            if path == "vendor/PIN":
                self.allow("vendor/PIN")
            elif csv_hash_cols is not None and any(run in field for i, field in enumerate(lines[n - 1].split(","))
                                                   if i in csv_hash_cols):
                self.allow("a hash column of config/*.csv")
            elif len(run) == 64 and (SHA256_WORD.search(context) or self.table_says_sha256(lines, n)):
                self.allow("SHA-256 (64 digits, named so)")
            elif len(run) == 40 and (OBJECT_WORD.search(context) or run.lower() in self.commits):
                self.allow("git object id (40 digits, a commit, tree or pin)")
            else:
                findings.append((n, f"{len(run)} hex digits, {short(run)} (key-sized: {len(run) // 2} bytes; not on "
                                    "the allow list of hashes)", run))
        for rx, what in ((BYTES16, "a 16-byte array literal"), (WORDS4, "a 16-byte array of four 32-bit words"),
                         (ESC16, "16 or more \\xNN escapes in a row")):
            for m in rx.finditer(text):
                findings.append((lineno(m.start()), f"{what}, {short(m.group(0))}", m.group(0)))
        for m in TOKEN.finditer(text):
            findings.append((lineno(m.start()), f"a token or private key: {m.group(0)[:11]}...", m.group(0)))
        return findings

    @staticmethod
    def table_says_sha256(lines, n):
        """Whether line n (1-based) is a row of a Markdown table whose header names SHA-256."""
        i = n - 1
        if not lines[i].lstrip().startswith("|"):
            return False
        while i > 0 and lines[i - 1].lstrip().startswith("|"):
            i -= 1
        return bool(SHA256_WORD.search(lines[i]))


def commits_of(runs):
    """The 40-digit runs that are commits of this repository."""
    runs = sorted(set(r.lower() for r in runs))
    if not runs:
        return set()
    out = git("cat-file", "--batch-check=%(objectname) %(objecttype)", data=("\n".join(runs) + "\n").encode())
    return {ln.split()[0] for ln in out.decode().splitlines() if ln.endswith(" commit")}


def forty_digit_runs(texts):
    found = set()
    for text in texts:
        found.update(m.group(0) for m in HEX_RUN.finditer(text) if len(m.group(0)) == 40)
    return found


def home_kind(path):
    """'record' or 'checker' when a home path in path is a note, else None (a finding)."""
    if path.startswith(NOTE_PREFIXES) or path in NOTE_FILES:
        return "record"
    if path in CHECKER_FILES:
        return "checker"
    return None


# ------------------------------------------------------------------------------------------------------------ tree
def check_tree(report):
    head = git("rev-parse", "HEAD").decode().strip()
    branch = git("rev-parse", "--abbrev-ref", "HEAD").decode().strip()
    dirty = git("status", "--porcelain", "--untracked-files=no").decode().strip()
    entries = []
    for rec in git("ls-tree", "-r", "-z", "-l", "--full-tree", "HEAD").decode("utf-8", "replace").split("\0"):
        if rec:
            meta, path = rec.split("\t", 1)
            mode, kind, oid, size = meta.split()
            entries.append((mode, kind, oid, size, path))
    report.line(f"release_check {time.strftime('%Y-%m-%d %H:%M')}: HEAD {head[:12]} ({branch}), {len(entries)} files"
                + (", uncommitted changes not read (commit them to check them)" if dirty else ""))

    bad_paths, bad_names, big, binaries = [], [], [], []
    for mode, kind, oid, size, path in entries:
        if kind != "blob":
            bad_paths.append(f"{path}: a {kind} entry (mode {mode})")
            continue
        p = path_problem(path)
        if p:
            bad_paths.append(f"{path}: {p}")
        p = name_problem(path)
        if p:
            bad_names.append(f"{path}: {p}")
        if int(size) > LIMIT:
            big.append(f"{path}: {int(size)} bytes, over the limit of {LIMIT} (1 MiB)")
    blobs = read_blobs(sorted({e[2] for e in entries if e[1] == "blob"}))
    texts = {}
    for mode, kind, oid, size, path in entries:
        if kind != "blob":
            continue
        data = blobs.get(oid, b"")
        if is_binary(data):
            if path not in KNOWN_BINARIES:
                binaries.append(f"{path}: a binary file ({int(size)} bytes), not one of the three known")
            what = game_header(data[:32774])
            if what:
                bad_names.append(f"{path}: {what} by its header")
        else:
            texts[path] = data.decode("utf-8", "replace")
    largest = max(((int(e[3]), e[4]) for e in entries if e[1] == "blob"), default=(0, "-"))
    n_binary = sum(1 for e in entries if e[1] == "blob" and is_binary(blobs.get(e[2], b"")))

    keys = Keys(commits_of(forty_digit_runs(texts.values())))
    key_findings, token_findings, home_findings, home_notes = [], [], [], {}
    for path, text in sorted(texts.items()):
        for n, what, _ in keys.scan(path, text):
            (token_findings if what.startswith("a token") else key_findings).append(f"{path}:{n}: {what}")
        for n, line in enumerate(text.split("\n"), 1):
            for m in HOME.finditer(line):
                kind = home_kind(path)
                if kind:
                    home_notes.setdefault((path, kind), []).append((n, m.group(0)))
                else:
                    home_findings.append(f"{path}:{n}: a home path, {m.group(0)}")

    allowed = ", ".join(f"{v} {k}" for k, v in sorted(keys.allowed.items())) or "none"
    report.check("paths", bad_paths, "no file under disc/ game/ generated/ vendor/ build/ out/ ref/ (but ref/README.md) "
                 "or the other ignored paths", f"{len(entries)} files")
    report.check("names", bad_names, "no game-data extension, game file name or game file header")
    report.check("size", big, "no file over 1 MiB", f"largest {largest[1]}, {largest[0]} bytes; limit {LIMIT}")
    report.check("binaries", binaries, "no binary file but the known three", f"{n_binary} binary files")
    report.check("keys", key_findings, "no key-sized hex run or 16-byte array", f"the allow list took {allowed}")
    report.check("tokens", token_findings, "no GitHub, GitLab or AWS token, no PEM block")
    n_notes = sum(len(v) for v in home_notes.values())
    report.check("home", home_findings, "no home path outside the record and the machine checks",
                 f"{n_notes} as notes in {len(home_notes)} files")
    for (path, kind), hits in sorted(home_notes.items()):
        why = "a task's record" if kind == "record" else "a machine check's own pattern"
        lines = sorted({n for n, _ in hits})
        firsts = ",".join(str(n) for n in lines[:4]) + (",..." if len(lines) > 4 else "")
        report.note(f"{path}:{firsts}: {len(hits)} home path(s), {why}, e.g. {hits[0][1]}")


# --------------------------------------------------------------------------------------------------------- history
def introducing_commit(value, path):
    out = git("log", "--exclude=refs/stash", "--all", "--reverse", "--format=%h %ad", "--date=short", "-S" + value,
              "--", path).decode().split("\n")
    return out[0] if out and out[0] else "a merge"


def check_history(report):
    t = time.time()
    commits = int(git("rev-list", "--exclude=refs/stash", "--all", "--count").decode())
    added = {}
    commit = None
    for line in git("log", "--exclude=refs/stash", "--all", "--reverse", "--no-renames", "--diff-filter=A",
                    "--name-only", "-m", "--format=commit %h").decode("utf-8", "replace").split("\n"):
        if line.startswith("commit "):
            commit = line[7:]
        elif line:
            added.setdefault(line, commit)
    findings = []
    for path, c in sorted(added.items()):
        for p in (path_problem(path), name_problem(path)):
            if p:
                findings.append(f"{path} (added in {c}): {p}")
    objects = {}
    for line in git("rev-list", "--exclude=refs/stash", "--all", "--objects").decode("utf-8", "replace").split("\n"):
        oid, _, path = line.partition(" ")
        if path:
            objects.setdefault(oid, path)
    check = git("cat-file", "--batch-check=%(objectname) %(objecttype)",
                data=("\n".join(objects) + "\n").encode()).decode().split("\n")
    blobs = read_blobs([ln.split()[0] for ln in check if ln.endswith(" blob")])
    texts = {}
    for oid, data in blobs.items():
        path = objects[oid]
        if is_binary(data):
            if path not in KNOWN_BINARIES:
                findings.append(f"{path} (blob {oid[:12]}): a binary file ({len(data)} bytes), not one of the three known")
            what = game_header(data[:32774])
            if what:
                findings.append(f"{path} (blob {oid[:12]}): {what} by its header")
        else:
            texts[oid] = data.decode("utf-8", "replace")
    keys = Keys(commits_of(forty_digit_runs(texts.values())))
    seen = set()
    for oid, text in texts.items():
        path = objects[oid]
        for n, what, value in keys.scan(path, text):
            if (path, value) in seen:
                continue
            seen.add((path, value))
            findings.append(f"{path}:{n} (blob {oid[:12]}, first in {introducing_commit(value, path)}): {what}")
    size = sum(len(b) for b in blobs.values())
    allowed = ", ".join(f"{v} {k}" for k, v in sorted(keys.allowed.items())) or "none"
    report.check("history", findings, "no game path, name or header, no binary but the known three, no key or token",
                 f"{commits} commits, {len(added)} paths ever added, {len(blobs)} file versions ({size / 1e6:.1f} MB) "
                 f"read in {time.time() - t:.1f} s; the allow list took {allowed}")


# --------------------------------------------------------------------------------------------------------- archive
def check_archive(report, zpath):
    name = os.path.basename(zpath)
    findings = []
    if not os.path.isfile(zpath):
        report.check("archive", [f"{zpath}: no such file (tools/bundle.sh --zip, tools/bundle_windows.sh --zip)"], "",
                     name)
        return
    m = re.match(re.escape(SLUG) + r"-(.+)-(macos-arm64|windows-x64)\.zip$", name)
    version, platform = (m.group(1), m.group(2)) if m else (None, None)
    if not m:
        findings.append(f"{zpath}: not named {SLUG}-VERSION-macos-arm64.zip or -windows-x64.zip")
    resources_text = []
    with zipfile.ZipFile(zpath) as z:
        infos = z.infolist()
        for info in infos:
            entry = info.filename.rstrip("/")
            p = name_problem(entry)
            if p:
                findings.append(f"{name}: {entry}: {p}")
            in_resources = ".app/Contents/Resources/" in entry + "/"
            if in_resources:
                rest = entry.split(".app/Contents/Resources/", 1)[-1] if ".app/Contents/Resources/" in entry else ""
                for part in rest.split("/"):
                    if part.lower() in RESOURCE_DATA_PARTS:
                        findings.append(f"{name}: {entry}: a game data path in the app's Resources ({part})")
            if info.is_dir():
                continue
            with z.open(info) as f:
                head = f.read(32774)
            what = game_header(head)
            if what:
                findings.append(f"{name}: {entry}: {what} by its header")
            if in_resources and platform == "macos-arm64" and not is_binary(head):
                resources_text.append((entry, z.read(info).decode("utf-8", "replace")))
        buildinfo = next((i for i in infos if os.path.basename(i.filename) == "BUILDINFO.txt"), None)
        if buildinfo:
            where, text = f"{name}:{buildinfo.filename}", z.read(buildinfo).decode("utf-8", "replace")
        else:
            beside = os.path.join(os.path.dirname(zpath), "BUILDINFO.txt")
            where = beside
            text = open(beside, encoding="utf-8", errors="replace").read() if os.path.isfile(beside) else None
    for entry, text_ in resources_text:
        for n, line in enumerate(text_.split("\n"), 1):
            for s in RESOURCE_STRINGS:
                if s in line:
                    findings.append(f"{name}: {entry}:{n}: holds {s}")
            for hm in HOME.finditer(line):
                findings.append(f"{name}: {entry}:{n}: a home path, {hm.group(0)}")
    detail = f"{name}: {len(infos)} entries"
    if text is None:
        findings.append(f"{zpath}: no BUILDINFO.txt in it or beside it")
    else:
        text = text.replace("\r", "")
        first = text.split("\n", 1)[0]
        vm = re.match(r"(.*?) (\S+) for ", first)
        bversion = vm.group(2) if vm else None
        cm = re.search(r"^Built from: (?:\S+ )?([0-9a-f]{40})\b", text, re.M)
        commit = cm.group(1) if cm else None
        if version and bversion != version:
            findings.append(f"{where}: is for version {bversion}, not this zip's {version} (another pack's?)")
        if not commit:
            findings.append(f"{where}: names no commit (no 'Built from: <40 digits>' line)")
        elif not commits_of([commit]):
            findings.append(f"{where}: commit {commit[:12]} is not in this repository")
        else:
            tags = git("tag", "--points-at", commit, "--list", "v[0-9]*").decode().split()
            detail += f", BUILDINFO.txt ({'in the zip' if buildinfo else 'beside it'}): {bversion}, commit {commit[:12]}"
            detail += f" (tag {', '.join(tags)})" if tags else ""
            if bversion and bversion.endswith("-dirty"):
                findings.append(f"{where}: {bversion} was built from a tree with uncommitted changes; a release is "
                                "packed from a clean commit")
            elif bversion and re.fullmatch(r"[0-9]+(\.[0-9]+)*", bversion):
                if f"v{bversion}" not in tags:
                    findings.append(f"{where}: version {bversion} names a release, but the tag v{bversion} is not on "
                                    f"commit {commit[:12]}")
            elif bversion and not commit.startswith(bversion.rsplit("-", 1)[-1]):
                findings.append(f"{where}: version {bversion} does not end in its commit {commit[:12]}")
    if platform == "macos-arm64":
        detail += f", {len(resources_text)} text files of Contents/Resources read"
    report.check("archive", findings, "no game file by name or header, BUILDINFO.txt names a clean commit of this "
                 "repository", detail)


# ---------------------------------------------------------------------------------------------------------- report
class Report:
    def __init__(self):
        self.rows, self.findings, self.notes = [], [], []

    def line(self, text):
        print(text, flush=True)

    def check(self, name, findings, claim, facts=""):
        """A row of the table: PASS with what it claims and its facts, or FAIL with the findings' count and facts."""
        self.findings += findings
        if findings:
            self.rows.append((name, "FAIL", f"{len(findings)} finding(s) above" + (f"; {facts}" if facts else "")))
        else:
            self.rows.append((name, "PASS", claim + (f"; {facts}" if facts else "")))

    def note(self, text):
        self.notes.append(text)

    def finish(self):
        for f in self.findings:
            print(f)
        for n in self.notes:
            print("note: " + n)
        if self.findings or self.notes:
            print()
        print(f"{'check':<10}{'result':<8}detail")
        for name, result, detail in self.rows:
            print(f"{name:<10}{result:<8}{detail}")
        failed = sum(1 for r in self.rows if r[1] == "FAIL")
        print(f"release_check: {'FAIL (' + str(failed) + ' of ' + str(len(self.rows)) + ' checks)' if failed else 'PASS'}"
              f" in {time.time() - T0:.1f} s")
        return 1 if failed else 0


def main(argv):
    history, archives, i = False, [], 0
    while i < len(argv):
        a = argv[i]
        if a == "--history":
            history = True
        elif a == "--archive":
            i += 1
            if i >= len(argv) or argv[i].startswith("--"):
                usage()
            while i < len(argv) and not argv[i].startswith("--"):
                archives.append(argv[i])
                i += 1
            continue
        elif a in ("-h", "--help"):
            with open("tools/release_check.sh", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("set -u"):
                        break
                    if line.startswith("#!"):
                        continue
                    print(line[2:].rstrip() if line.startswith("# ") else line[1:].rstrip())
            return 0
        else:
            usage()
        i += 1
    report = Report()
    check_tree(report)
    if history:
        check_history(report)
    for z in archives:
        check_archive(report, z)
    return report.finish()


sys.exit(main(sys.argv[1:]))
PY
