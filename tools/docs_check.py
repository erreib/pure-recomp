#!/usr/bin/env python3
"""Checks that the docs name only what exists (task 053).

    python3 tools/docs_check.py [--quiet] [FILE.md ...]

The files: README.md, ref/README.md, patches/README.md and every .md under docs/ except docs/tasks/ (the task files
are the record: they cite what existed when they were written, and are not rewritten). Four checks, on fenced code
blocks too except for links:

  paths    every `tools/...`, `src/...`, `config/...`, `docs/...`, `packaging/...` and `third_party/...` path a doc names
           exists in the checkout: a file, a directory, a glob that matches something, `a.{hpp,cpp}` braces with every
           member present, or a stem (`src/tools/ge_replay` for `ge_replay.cpp`); a placeholder in capitals (TRACK,
           MODE, NAME, FILE, DIR and the like, `PLACEHOLDERS`) stands for any name
           (`config/pad_scripts/drive/TRACK.txt`). A path counts when it starts a word (not
           `vendor/portablekit/tools/...` or `~/dev/x/src/...`). docs/codegen-baseline.md and docs/research.md are
           spike reports about other repositories (PortableKit, Yakumo, PSPRecomp), whose `src/` and `tools/` are
           theirs, and the history files under docs/history/ are dated records that keep the
           names of their day: this check skips both kinds.
  links    every relative Markdown link `[text](target)` resolves: the file exists, and a `#anchor` names a heading of
           it (GitHub's rule: lower case, punctuation dropped, spaces to hyphens, -1, -2 for repeats).
  patches  every patch named as `NNNN-slug` (with or without `patches/` and `.patch`) is a file in patches/; every
           "patch NNNN" or "patches NNNN" without its slug is reported: since task 052 the numbers that tasks
           001 to 048 used name other patches (patches/README.md maps them). "old NNNN" is how a doc names an old number on
           purpose. The mapping table of patches/README.md ("Old numbers") is skipped, and a history file may cite
           an old patch by the name that table gives it (`patches/0009-ge-backend-seam.patch` as it was then).
  tasks    every `docs/tasks/NNN` (with or without its slug) is a task file.

Exit 0 when every check passes, else 1 with one line per finding (FILE:LINE: what). Standard library only.
"""
import argparse
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Spike reports whose tools/ and src/ paths are other repositories' (they say so in their opening lines).
EXTERNAL = {"docs/codegen-baseline.md", "docs/research.md"}
# The words the docs use for "any name" inside a path.
PLACEHOLDERS = ("TRACK", "MODE", "NNNN", "NNN", "NAME", "FILE", "DIR", "CELL", "SCENE", "ADDR", "TAG", "PACK")
PATH_PREFIXES = ("tools/", "src/", "config/", "docs/", "packaging/", "third_party/")
PATH_RE = re.compile(r"(?<![\w./~-])((?:%s)[\w.{},*+/-]*)" % "|".join(re.escape(p) for p in PATH_PREFIXES))
LINK_RE = re.compile(r"(?<!!)\[([^\]]*)\]\(([^)\s]+)\)")
PATCH_NAME_RE = re.compile(r"(?<![\w.])(?:patches/)?(0\d{3})-([a-z][a-z0-9-]*[a-z0-9])(?:\.patch)?")
PATCH_BARE_RE = re.compile(r"(?<![\w-])([Pp]atch(?:es)?)\s+(0\d{3})(?!-[a-z])")
TASK_RE = re.compile(r"docs/tasks/(\d{3})([\w.-]*)")


def tracked_docs():
    """The files the check reads by default."""
    files = ["README.md", "ref/README.md", "patches/README.md"]
    for path in sorted(glob.glob(os.path.join(ROOT, "docs", "**", "*.md"), recursive=True)):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")   # forward slashes on Windows too (task 054)
        if not rel.startswith("docs/tasks/"):
            files.append(rel)
    return files


def slug(heading):
    """GitHub's anchor for a heading's text."""
    text = re.sub(r"`|\*\*|__", "", heading.strip().lower())
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def anchors(path):
    """Every anchor the Markdown file at path offers."""
    seen, out = {}, set()
    fence = False
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.lstrip().startswith("```"):
                fence = not fence
                continue
            m = re.match(r"#{1,6}\s+(.*?)\s*#*\s*$", line)
            if m and not fence:
                base = slug(m.group(1))
                n = seen.get(base, 0)
                seen[base] = n + 1
                out.add(base if n == 0 else f"{base}-{n}")
    return out


def expand(path):
    """The paths a {a,b} brace form stands for."""
    m = re.search(r"\{([^{}]*)\}", path)
    if not m:
        return [path]
    out = []
    for part in m.group(1).split(","):
        out += expand(path[:m.start()] + part + path[m.end():])
    return out


def exists(path, bases):
    """Whether path names something under one of bases (a file, a directory, a glob's match or a stem)."""
    path = re.sub(r"(?<![A-Za-z])(%s)(?![A-Za-z])" % "|".join(PLACEHOLDERS), "*", path)
    for base in bases:
        full = os.path.join(base, path)
        if any(c in path for c in "*?["):
            if glob.glob(full):
                return True
        elif os.path.exists(full) or glob.glob(glob.escape(full.rstrip("/")) + ".*"):
            return True
    return False


def clean(token):
    """A path token without the prose around it."""
    token = token.rstrip(".,:;")
    while token.endswith(")") and token.count("(") < token.count(")"):
        token = token[:-1].rstrip(".,:;")
    if token.count("{") != token.count("}"):
        token = token.split("{")[0]
    return token


_OLD = []


def old_stems():
    """The old patch names of patches/README.md's mapping table (\"Old numbers\"), which history files may cite."""
    if not _OLD:
        section = False
        with open(os.path.join(ROOT, "patches", "README.md"), encoding="utf-8") as f:
            for line in f:
                if line.startswith("#"):
                    section = line.strip("# \n") == "Old numbers"
                m = re.match(r"\|\s*(0\d{3}-[a-z0-9-]+)\s*\|", line) if section else None
                if m:
                    _OLD.append(m.group(1))
        _OLD.append("")  # read once, even when the table is empty
    return _OLD


def check_file(rel, patch_stems, task_files, findings):
    path = os.path.join(ROOT, rel)
    history = rel.startswith("docs/history/")
    bases = [ROOT]
    fence = False
    skip_section = False
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    for number, line in enumerate(lines, 1):
        where = f"{rel}:{number}"
        if line.lstrip().startswith("```"):
            fence = not fence
            continue
        heading = re.match(r"#{1,6}\s+(.*)", line)
        if heading and not fence:
            skip_section = rel == "patches/README.md" and heading.group(1).strip() == "Old numbers"
        if skip_section:
            continue
        # Patches named with their slug.
        for m in PATCH_NAME_RE.finditer(line):
            stem = f"{m.group(1)}-{m.group(2)}"
            if stem in patch_stems or (history and stem in old_stems()):
                continue
            findings.append(f"{where}: patch {stem} is not in patches/" +
                            (" (an old name: patches/README.md, \"Old numbers\")" if stem in old_stems() else ""))
        # Patches named by a bare number.
        # (A citation broken across two lines counts on the first: the next line's first word is read with it.)
        following = lines[number].split()[:1] if number < len(lines) else []
        joined = " ".join([line] + following)
        for m in PATCH_BARE_RE.finditer(joined):
            if m.start() >= len(line):
                continue
            previous = lines[number - 2].split()[-1:] if number > 1 and lines[number - 2].strip() else []
            before = " ".join(previous + [line[:m.start()]]).rstrip().lower()
            if not before.endswith("old"):
                findings.append(f"{where}: '{m.group(0)}' names a patch by number alone (patches/README.md maps "
                                "the old numbers; give NNNN-slug)")
        for m in TASK_RE.finditer(line):
            num, rest = m.group(1), m.group(2).rstrip(".,:;")
            names = task_files.get(num, [])
            if not names:
                findings.append(f"{where}: docs/tasks/{num} does not exist")
            elif rest.startswith("-") and not any(n == num + rest or n == num + rest + ".md" for n in names):
                findings.append(f"{where}: docs/tasks/{num}{rest} does not exist (the task file is {names[0]})")
        for m in LINK_RE.finditer("" if fence else line):
            target = m.group(2)
            if re.match(r"[a-z]+:", target) or target.startswith("/"):
                continue
            file_part, _, anchor = target.partition("#")
            dest = os.path.normpath(os.path.join(os.path.dirname(path), file_part)) if file_part else path
            if not os.path.exists(dest):
                findings.append(f"{where}: link {target} does not resolve")
            elif anchor and dest.endswith(".md") and anchor not in anchors(dest):
                findings.append(f"{where}: link {target}: no heading with that anchor")
        if history or rel in EXTERNAL:
            continue
        for m in PATH_RE.finditer(line):
            token = clean(m.group(1))
            if token.rstrip("/") in ("tools", "src", "config", "docs", "packaging", "third_party") or \
                    token.startswith("docs/tasks/"):
                continue
            missing = [p for p in expand(token) if not exists(p, bases)]
            if missing:
                findings.append(f"{where}: {token} does not exist" + (f" ({', '.join(missing)})" if missing != [token]
                                                                       else ""))


def main():
    parser = argparse.ArgumentParser(description="Checks that the docs name only what exists.")
    parser.add_argument("files", nargs="*", help="the docs to check (default: README.md, ref/README.md, "
                        "patches/README.md and docs/ without docs/tasks/)")
    parser.add_argument("--quiet", action="store_true", help="print only the findings and the verdict")
    args = parser.parse_args()
    files = [os.path.relpath(os.path.abspath(f), ROOT) for f in args.files] or tracked_docs()
    patch_stems = {os.path.basename(p)[:-len(".patch")] for p in glob.glob(os.path.join(ROOT, "patches", "*.patch"))}
    task_files = {}
    for p in sorted(glob.glob(os.path.join(ROOT, "docs", "tasks", "[0-9][0-9][0-9]-*.md"))):
        name = os.path.basename(p)
        task_files.setdefault(name[:3], []).append(name)
    findings = []
    for rel in files:
        check_file(rel, patch_stems, task_files, findings)
    for line in findings:
        print(line)
    if not args.quiet or findings:
        print(f"docs_check: {len(files)} files, {len(findings)} findings: {'FAIL' if findings else 'PASS'}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
