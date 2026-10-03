#!/usr/bin/env bash
# Rebuild release/<channel> from the channel branch and open/update its release PR.
# Env: CHANNEL BASE BETA_BRANCH PLG CHANGELOG SCRIPTS GIT_USER GIT_EMAIL DRY_RUN GH_TOKEN
set -euo pipefail

: "${CHANNEL:?}" "${BASE:?}" "${PLG:?}" "${CHANGELOG:?}" "${SCRIPTS:?}" "${GIT_USER:?}" "${GIT_EMAIL:?}"
BETA_BRANCH="${BETA_BRANCH:-}"
DRY_RUN="${DRY_RUN:-false}"
RB="release/$CHANNEL"
PLGR="python3 $SCRIPTS/plg_release.py"
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

. "$SCRIPTS/plg_release_git.sh"
plg_git_setup
git fetch --no-tags origin "+refs/heads/$BASE:refs/remotes/origin/$BASE"
git fetch --no-tags origin "+refs/heads/$RB:refs/remotes/origin/$RB" 2>/dev/null || true
[ -z "$BETA_BRANCH" ] || git fetch --no-tags origin "+refs/heads/$BETA_BRANCH:refs/remotes/origin/$BETA_BRANCH"
git fetch --tags origin

OLD_SHA=$(git rev-parse -q --verify "origin/$RB" || true)
OLD_SYNC=""
OLD_SYNC_BETA=""
OLD_CL=""
if [ -n "$OLD_SHA" ]; then
  # the trailers sit on this job's own commit; edits pushed to the PR since then sit on top of it
  trailers=$(git log --format=%B "origin/$BASE..origin/$RB")
  OLD_SYNC=$(sed -n 's/^Release-Synced: //p' <<<"$trailers" | sed -n 1p)
  OLD_SYNC_BETA=$(sed -n 's/^Release-Synced-Beta: //p' <<<"$trailers" | sed -n 1p)
  OLD_CL="$SCRATCH/old-changelog.md"
  git show "origin/$RB:$CHANGELOG" > "$OLD_CL" 2>/dev/null || OLD_CL=""
  # The rebuild below carries over only the notes: stop rather than drop anything else pushed to the PR.
  # Beta work is never an edit here, promoted by tag or merged whole by an older refresh; ^ per ref, as --not toggles.
  not_promoted=()
  [ -z "$BETA_BRANCH" ] || [ "$BASE" = "$BETA_BRANCH" ] || not_promoted=("^origin/$BETA_BRANCH")
  if [ -n "$OLD_SYNC_BETA" ] && git rev-parse -q --verify "refs/tags/$OLD_SYNC_BETA" >/dev/null; then
    not_promoted+=("^refs/tags/$OLD_SYNC_BETA")
  fi
  edited=$(git log --no-merges --format= --name-only "origin/$BASE..origin/$RB" "${not_promoted[@]}" \
    -- . ":(top,exclude)$CHANGELOG" | sort -u)
  if [ -n "$edited" ]; then
    echo "::error::$RB changes more than $CHANGELOG ($(tr '\n' ' ' <<<"$edited")); a refresh rebuilds it from $BASE and would drop that. Move it to $BASE, or remove it from $RB, then push again."
    exit 1
  fi
fi

git switch -q -C "$RB" "origin/$BASE"

# Promotion PR: bring the newest beta release (its tag, never unreleased work on beta) into the stable channel.
promote=""
if [ "$CHANNEL" = stable ] && [ -n "$BETA_BRANCH" ] && git cat-file -e "origin/$BETA_BRANCH:$CHANGELOG" 2>/dev/null; then
  beta_cl="$SCRATCH/beta-changelog.md"
  git show "origin/$BETA_BRANCH:$CHANGELOG" > "$beta_cl"
  beta_tag=$($PLGR last-beta --changelog "$beta_cl")
  if [ -n "$beta_tag" ] && git rev-parse -q --verify "refs/tags/$beta_tag" >/dev/null \
      && ! git merge-base --is-ancestor "refs/tags/$beta_tag" HEAD; then
    promote="$beta_tag"
    . "$SCRIPTS/plg_release_merge.sh"
    plg_merge "refs/tags/$beta_tag" stable
    git commit -q -m "chore(release): merge $beta_tag into $BASE for the next stable"
  fi
fi

# Seed: commit subjects on the channel branch since the last sync, plus beta notes the PR has not taken yet.
since="$OLD_SYNC"
if [ -z "$since" ] || ! git merge-base --is-ancestor "$since" "origin/$BASE" 2>/dev/null; then
  since=$($PLGR since-ref --changelog "$CHANGELOG" --channel "$CHANNEL")
fi
seed_args=(--since "$since" --until "origin/$BASE")
# the promoted beta's notes already describe its commits, so they are not listed again from master
[ -z "$promote" ] || seed_args+=(--beta-sections --beta-after "$OLD_SYNC_BETA" --exclude "refs/tags/$promote")
carry=()
[ -z "$OLD_CL" ] || carry=(--carry-from "$OLD_CL")
$PLGR seed --changelog "$CHANGELOG" --channel "$CHANNEL" "${carry[@]}" "${seed_args[@]}"

# Capture first: piping straight into grep -c would turn a notes failure into "nothing to release".
notes=$($PLGR notes --changelog "$CHANGELOG" --version Unreleased)
count=$(printf '%s\n' "$notes" | grep -c '^- ' || true)
if [ "$count" -eq 0 ] && [ -z "$OLD_SHA" ]; then
  echo "::notice::nothing to release on $BASE — no release PR opened"
  exit 0
fi

# --allow-empty: an emptied Unreleased section still has to record the Release-Synced trailer.
sync="Release-Synced: $(git rev-parse "origin/$BASE")"
[ -z "$promote" ] || sync+=$'\n'"Release-Synced-Beta: $promote"
git add "$CHANGELOG"
git commit -q --allow-empty -m "chore($BASE): release changelog" -m "$sync"

if [ "$DRY_RUN" = true ]; then
  echo "::notice::dry run — would push $RB and open/update the release PR"
  git log --oneline "origin/$BASE..HEAD"
  git diff "origin/$BASE" -- "$CHANGELOG"
  exit 0
fi

if [ -n "$OLD_SHA" ]; then
  git push -q --force-with-lease="refs/heads/$RB:$OLD_SHA" origin "$RB"
else
  git push -q origin "$RB"
fi

body="$SCRATCH/pr-body.md"
{
  echo "Merge this PR to cut the next **$CHANNEL** release. Edit the Unreleased section of \`$CHANGELOG\` on this branch first; the release job stamps the version, renders it into the plugin manifest, and attaches the package."
  echo
  echo "Bullets are copied from commit subjects, and a stable release refuses any bullet that is still word for word the copy (those ending in a commit hash, for example): reword or delete each one."
  echo
  # generated PR: the release check enforces the changelog rules, so keep CodeRabbit off it
  echo "@coderabbitai ignore"
  [ -z "$promote" ] || echo "This PR also brings beta release \`$promote\` into \`$BASE\` — merge it with a merge commit, not a squash."
  echo
  echo "## Unreleased"
  echo
  printf '%s\n' "$notes"
} > "$body"

pr=$(gh pr list --head "$RB" --base "$BASE" --state open --json number --jq '.[0].number // empty')
if [ -z "$pr" ]; then
  gh pr create --head "$RB" --base "$BASE" --title "chore($BASE): release" --body-file "$body"
else
  gh pr edit "$pr" --body-file "$body" >/dev/null
  echo "updated release PR #$pr"
fi
