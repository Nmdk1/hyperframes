#!/usr/bin/env bash
# Daily upstream check for one of Nmdk1's forks. Read FORK.md for the why.
# Settings for this fork live in .fork/config; this script is identical in every fork.
#
#   bash .fork/sync.sh            check once per day (no-op if already checked today)
#   bash .fork/sync.sh --force    check now even if already checked today
#   bash .fork/sync.sh --no-push  do everything locally but do not push to origin
#
# What it does: main on this fork is always exactly
#   <latest upstream version>  +  one "fork: overlay" commit
# "Latest upstream version" is the newest vX.Y.Z release tag (TRACK=release) or the
# tip of the upstream branch (TRACK=branch). The overlay commit carries .fork/,
# FORK.md, and the pointer block at the top of each file in POINTER_TARGETS.
# On every daily check the overlay commit is rebuilt on the latest upstream version
# and force-pushed (with a lease) to origin/main.
set -euo pipefail

force=0; push=1
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    --no-push) push=0 ;;
    *) echo "unknown option: $arg" >&2; exit 64 ;;
  esac
done

root=$(git rev-parse --show-toplevel)
cd "$root"

# Defaults, overridden by .fork/config.
UPSTREAM_URL=""
TRACK="release"
UPSTREAM_BRANCH="main"
POINTER_TARGETS="CLAUDE.md AGENTS.md"
LOCAL_TZ="America/Chicago"
# shellcheck disable=SC1091
. .fork/config
[ -n "$UPSTREAM_URL" ] || { echo "fork-sync: STOP. UPSTREAM_URL missing from .fork/config." >&2; exit 64; }

BEGIN_MARK="<!-- NMDK1-FORK:BEGIN"
END_MARK="<!-- NMDK1-FORK:END -->"
state_file=".fork/state"
today=$(TZ="$LOCAL_TZ" date +%F)

read_state() { [ -f "$state_file" ] || return 0; sed -n "s/^$1=//p" "$state_file" | head -1; }

# 1. Never discard someone's uncommitted work.
if [ -n "$(git status --porcelain)" ]; then
  echo "fork-sync: STOP. Uncommitted changes in $root. Commit or stash them, then re-run." >&2
  git status --short >&2
  exit 2
fi

# 2. Catch up with origin first: another session may already have checked today.
git fetch --quiet --depth 1 origin main
origin_main=$(git rev-parse origin/main)
if [ "$(git rev-parse HEAD)" != "$origin_main" ]; then
  if git merge-base --is-ancestor "$origin_main" HEAD 2>/dev/null; then
    : # local is ahead of origin (unpushed fork-file edits): keep them, they ride along
  elif git merge-base --is-ancestor HEAD "$origin_main" 2>/dev/null \
       || git log -1 --format=%s HEAD | grep -q '^fork: overlay'; then
    git checkout --quiet -B main "$origin_main"   # stale local copy: take origin's
  else
    echo "fork-sync: STOP. Local HEAD is not origin/main and is not an overlay commit." >&2
    echo "Someone committed here directly. Push or move that work to a branch, then re-run." >&2
    exit 3
  fi
fi

last_checked=$(read_state checked)
current=$(read_state version)
if [ "$force" = 0 ] && [ "$last_checked" = "$today" ]; then
  echo "fork-sync: Already checked today ($today). On upstream $current. Carry on."
  exit 0
fi

# 3. Find the latest upstream version and fetch it.
if [ "$TRACK" = "release" ]; then
  latest=$(git ls-remote --tags --refs "$UPSTREAM_URL" 'v*' \
    | awk -F/ '{print $3}' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)
  [ -n "$latest" ] || { echo "fork-sync: STOP. Could not read release tags from $UPSTREAM_URL." >&2; exit 4; }
  git fetch --quiet --depth 1 "$UPSTREAM_URL" "refs/tags/$latest:refs/tags/$latest"
  upstream_commit=$(git rev-parse "$latest^{commit}")
elif [ "$TRACK" = "branch" ]; then
  git fetch --quiet --depth 1 "$UPSTREAM_URL" "refs/heads/$UPSTREAM_BRANCH" \
    || { echo "fork-sync: STOP. Could not fetch $UPSTREAM_BRANCH from $UPSTREAM_URL." >&2; exit 4; }
  upstream_commit=$(git rev-parse FETCH_HEAD)
  latest="$UPSTREAM_BRANCH@$(git rev-parse --short=12 FETCH_HEAD)"
else
  echo "fork-sync: STOP. TRACK in .fork/config must be release or branch." >&2; exit 64
fi

synced_on=$(read_state synced_on)
if [ "$latest" != "$current" ]; then
  synced_on="$today"
  echo "fork-sync: Newer upstream version found: ${current:-none} -> $latest. Replacing fork contents."
else
  echo "fork-sync: Upstream is still $latest. Recording today's check."
fi

# 4. Save fork-owned files, replace everything with the upstream version, restore them.
keep=$(mktemp -d)
cp -R .fork "$keep/fork"
[ -f FORK.md ] && cp FORK.md "$keep/FORK.md"
git checkout --quiet -B main "$upstream_commit"
rm -rf .fork && cp -R "$keep/fork" .fork
[ -f "$keep/FORK.md" ] && cp "$keep/FORK.md" FORK.md
rm -rf "$keep"

# 5. Re-insert the pointer block at the very top of each agent instruction file
#    (the file is created if upstream does not have one).
for f in $POINTER_TARGETS; do
  body=""
  if [ -f "$f" ]; then
    body=$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
      index($0,b)==1 {skip=1; next}
      skip && index($0,e)==1 {skip=0; drop_blank=1; next}
      skip {next}
      drop_blank && /^$/ {drop_blank=0; next}
      {drop_blank=0; print}' "$f")
  fi
  if [ -n "$body" ]; then
    { cat .fork/pointer.md; echo; printf '%s\n' "$body"; } > "$f.tmp"
  else
    cat .fork/pointer.md > "$f.tmp"
  fi
  mv "$f.tmp" "$f"
done

# 6. Record state and commit the single overlay commit.
cat > "$state_file" <<EOF
# Written by .fork/sync.sh. Do not edit by hand.
version=$latest
upstream_commit=$upstream_commit
synced_on=$synced_on
checked=$today
EOF
# shellcheck disable=SC2086
git add -A .fork FORK.md $POINTER_TARGETS
git commit --quiet --no-verify -m "fork: overlay on upstream $latest (checked $today)"

# 7. Publish. The lease refuses the push if origin moved since step 2.
if [ "$push" = 1 ]; then
  if ! git push --quiet --force-with-lease="main:$origin_main" origin main; then
    echo "fork-sync: Push refused (origin changed underneath, or no push access)." >&2
    echo "Re-run the script once. If it fails again, tell Michael." >&2
    exit 5
  fi
  echo "fork-sync: Done. Fork is on upstream $latest, checked $today."
else
  echo "fork-sync: Done locally (not pushed). Fork is on upstream $latest."
fi
