#!/usr/bin/env bash
# After a stable release: merge the stable branch into beta, keeping beta's release fields, and re-render its CHANGES.
# Env: BASE BETA_BRANCH PLG CHANGELOG SCRIPTS GIT_USER GIT_EMAIL VERSION DRY_RUN
set -euo pipefail

: "${BASE:?}" "${BETA_BRANCH:?}" "${PLG:?}" "${CHANGELOG:?}" "${SCRIPTS:?}" "${GIT_USER:?}" "${GIT_EMAIL:?}" "${VERSION:?}"
DRY_RUN="${DRY_RUN:-false}"
PLGR="python3 $SCRIPTS/plg_release.py"

. "$SCRIPTS/plg_release_git.sh"
. "$SCRIPTS/plg_release_merge.sh"
plg_git_setup
git fetch --no-tags origin "+refs/heads/$BASE:refs/remotes/origin/$BASE" "+refs/heads/$BETA_BRANCH:refs/remotes/origin/$BETA_BRANCH"
git switch -q -C "$BETA_BRANCH" "origin/$BETA_BRANCH"

plg_merge "origin/$BASE" beta
$PLGR check --changelog "$CHANGELOG" --plg "$PLG" --channel beta --branch "$BETA_BRANCH"

# --allow-empty: an already-merged base leaves nothing staged, and that is not a failure.
git commit -q --allow-empty -m "chore(release): merge $BASE into $BETA_BRANCH after $VERSION [skip ci]"

if [ "$DRY_RUN" = true ]; then
  echo "::notice::dry run — would push $BETA_BRANCH"
  git show --stat HEAD
  exit 0
fi
git push -q origin "HEAD:$BETA_BRANCH"
