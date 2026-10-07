# How this project is run

A short orientation for anyone picking the project up, a new session included. The details are in docs/status.md
(the state), docs/decisions.md (the choices and why), docs/verification.md (the checks) and docs/tasks/ (the record).

## What the asset is

The thing worth the most here is not the Wipeout Pure port by itself. It is two things that carry over to every
project planned after it (a Pulse recomp, the mashup, the expanded version, a Windows build):

- **the framework**: PortableKit as vendored (the runtime: kernel, HLE, GE state, audio, video, saves), our nine
  patches to it (docs/upstream.md says which belong upstream), and our native Metal backend behind the backend seam;
- **the harness**: the picture suite against PPSSPP, the campaign sweep, the fidelity audit, the scorecard, the VFPU
  probes and models, the save and audio checks, the refactor check, and the task protocol that runs them.

The Pure port was the first project to use both and the one that proved they work. Keep them reusable: a change that
only Pure needs goes in the profile, not the framework; a check that only Pure needs stays a route, not a tool.

## How the work is split

One planning session (Fable) does the research, the mapping of hard parts, the briefs, the reviews and the merges.
Workers (Opus subagents) do briefed tasks on their own branches and worktrees, each with a Verify command, a
May-touch list and an escalation rule, and report in a fixed shape. Only the planning session merges, after rerunning
the brief's Verify from the main checkout; `main` moves only when Erik says so, and only Erik pushes. The task files
under docs/tasks/ are the record: never rewritten, only appended to.

Compared with a recomp built by one person over months, this is cheaper per task, faster, tested more and written
up more. The parallelism is real: several tasks run at once on disjoint files, each proven on its own.

## The trade-off, and what substitutes for it

A solo author carries the whole port in their head: every quirk and every reason. Nobody on this project does. The
planning session loses context between sessions, and each worker only ever sees its own task. What replaces that
memory:

- **the docs as reference**: each describes the repository as it is, with the measurements that led there moved to
  docs/history/ and linked, and `tools/docs_check.py` keeping every path, patch and task they name real;
- **the task files as the record**: what was asked, what was found, what was verified, in the worker's words and the
  reviewer's;
- **the scorecard and the suite as the memory of what is right**: a change is judged by the same numbers every time,
  not by recollection.

The organisation pass of 2026-10-07 (tasks 049 to 053) was partly about making these good enough to hand the
project to a stranger.

## What to do with a wrong premise

Briefs carry facts, and some have been wrong (register numbers, a rounding rule that turned out to be the emulator's
compiler). The protocol expects it: a worker that finds the brief's premise false reports it with evidence instead
of building on it, and the review records the correction. Prefer a measured answer over a documented one when the
two disagree, and say which it was.
