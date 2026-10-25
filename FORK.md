# Nmdk1 fork of heygen-com/hyperframes

This is Michael Shaffer's fork of [heygen-com/hyperframes](https://github.com/heygen-com/hyperframes), kept in his own GitHub account so any agent working for him can find it and so a copy survives if upstream disappears. HyperFrames turns HTML, CSS and seekable animation into deterministic MP4 video; Michael uses it for StrideIQ marketing films.

Use it from this checkout (`npx hyperframes`, the skills under `skills/`). A film that must re-render identically later should pin `npx hyperframes@<version>` to the version in `.fork/state`.

## The daily rule

The first agent to use this repo on a given day (America/Chicago date) runs, from the repo root:

```bash
bash .fork/sync.sh
```

before doing anything else with the repo. Every later agent that day runs the same command; it prints `Already checked today` and exits in about a second. The date of the last check is stored in `.fork/state`, which is committed, so the rule holds across fresh clones and new sessions.

## What the script does

This fork tracks the newest upstream release tag (`vX.Y.Z`), because releases are the tested versions. Settings are in `.fork/config`.

1. Stops if the working tree has uncommitted changes. It never discards work.
2. Fetches `origin/main` so it sees a check another session already made today.
3. Reads the latest upstream version from `https://github.com/heygen-com/hyperframes`.
4. If it is newer than the one in `.fork/state`, it replaces the whole fork with it: `main` is reset to the upstream commit, and the fork-owned files (`.fork/`, `FORK.md`) are restored on top.
5. Re-inserts the instruction block from `.fork/pointer.md` at the top of each file listed in `POINTER_TARGETS` (creating the file if upstream has none), so every agent sees the daily rule first.
6. Writes `.fork/state` (version, upstream commit, date the version last changed, date checked) and makes a single commit, `fork: overlay on upstream <version> (checked YYYY-MM-DD)`.
7. Force-pushes to `origin/main` with a lease, so it refuses rather than overwrites if another session pushed in between.

The result is always the same shape: `main` = the latest upstream version + exactly one overlay commit.

## Where things live

| Path | Purpose |
| --- | --- |
| `.fork/sync.sh` | The daily check and replace script (identical in all of Michael's forks) |
| `.fork/config` | Upstream URL, release or branch tracking, files that get the pointer block |
| `.fork/pointer.md` | The instruction block inserted at the top of the agent instruction files |
| `.fork/state` | Current upstream version and the date of the last check |
| `FORK.md` | This file |

Everything else is upstream's and is replaced on every sync. Do not edit upstream files here; changes would be wiped. If a change is ever needed, put it on a separate branch and tell Michael.

## If it fails

| Exit | Meaning | What to do |
| --- | --- | --- |
| 2 | Uncommitted changes | Commit or stash them, then re-run |
| 3 | Someone committed directly on `main` | Move that work to a branch, then re-run |
| 4 | Upstream unreadable | Network issue; work from the current version and tell Michael |
| 5 | Push refused | Re-run once; if it fails again, tell Michael |

Options: `--force` checks again even if today is already recorded; `--no-push` does everything locally without pushing.

## Reproducible results

The fork moves forward on its own. Anything that must be reproduced exactly later should record the `version` and `upstream_commit` from `.fork/state` it was made with.
