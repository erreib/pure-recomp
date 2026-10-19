# How this project is run

A short orientation for anyone picking the project up, a new session included. The details are in docs/status.md
(the state), docs/decisions.md (the choices and why), docs/verification.md (the checks) and docs/tasks/ (the record).

## What the asset is

The thing worth the most here is not the Wipeout Pure port by itself. It is two things that carry over to every
project planned after it (a Pulse recomp, the mashup, the expanded version, a Windows build):

- **the framework**: PortableKit as vendored (the runtime: kernel, HLE, GE state, audio, video, saves), our patches
  to it (patches/README.md lists them; docs/upstream.md says which belong upstream), and our native Metal backend
  behind the backend seam;
- **the harness**: the picture suite against PPSSPP, the campaign sweep, the fidelity audit, the scorecard, the VFPU
  probes and models, the save and audio checks, the refactor check, and the task protocol that runs them.

The Pure port was the first project to use both and the one that proved they work. Keep them reusable: a change that
only Pure needs goes in the profile, not the framework; a check that only Pure needs stays a route, not a tool.

## How the work is split

One planning session (the strongest model available) does the research, the mapping of hard parts, the briefs, the
reviews and the merges. Workers (Opus subagents) do briefed tasks on their own branches and worktrees, each with a
Verify command, a May-touch list and an escalation rule, and report in a fixed shape. Only the planning session
merges, after the gate of rule 3 below; `main` moves only when Erik says so, and only Erik pushes. The task files
under docs/tasks/ are the record: never rewritten, only appended to.

Compared with a recomp built by one person over months, this is cheaper per task, faster, tested more and written
up more. The parallelism is limited by game runs on one machine (1.3 workers at a time on average); the split's
real gain is that a worker's large context never lands in the planning session's.

## Working rules (2026-10-19)

From the audit of Oct 5 to 15: workers took 77% of the tokens, the planning session's context ran at a median of
402K tokens a call, the planning cost per dispatch rose from 8M to 21M tokens as briefs and docs grew, and 54% of
commits touched only docs, status or task files. Only 5% of tasks needed a second round for the work itself. The
split stays; these rules cut what everyone reads and writes.

1. **Size.** A worker is for work with long runs or wide exploration. A small change (a few files, a cheap check: a
   doc fix, a one-function fix, a patch under about 100 lines) is made by the planning session directly.
2. **Briefs.** Read-first names sections, not whole files, about 30K tokens of reading at most. Facts the worker
   needs are written into the brief.
3. **One gate.** The worker runs Verify and keeps its logs under out/. The planning session reads them and reruns
   only what the merge can change (conflicts, code changed after the worker's run) and any window check the worker
   could not run.
4. **Window runs need Erik's screen**: the game window in front and uncovered (a covered window runs without
   vsync and measures nothing). Workers run no window check unless the brief says the screen is booked; they list
   the window checks their change needs, and the planning session runs them in one batch when Erik books the screen.
5. **Status is current state only**: what is merged, open and next, about 25 KB. An arc's narrative goes in its
   task file's Review or docs/history/. Routine events (a repack, a fast-forward) get no status commit of their own.
6. **Sessions.** One planning session per arc, started fresh from docs/status.md, rather than one long session: the
   re-read context, not the reasoning, is most of the cost.
7. **Task numbers.** The Mac takes 092 to 499, the rig 500 and up (077, 078 and 091 each exist twice).
8. **One fact, one place.** A check is specified in its script's header; docs/developing.md gives it one line;
   docs/verification.md says what it guards and when it runs. Measurements stay in task files and docs/history/.

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
