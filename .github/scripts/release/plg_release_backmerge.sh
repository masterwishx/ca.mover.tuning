#!/usr/bin/env bash
# After a stable release: merge the stable branch into beta, keeping beta's manifest, and re-render its CHANGES.
# Env: BASE BETA_BRANCH PLG CHANGELOG SCRIPTS GIT_USER GIT_EMAIL VERSION DRY_RUN
set -euo pipefail

: "${BASE:?}" "${BETA_BRANCH:?}" "${PLG:?}" "${CHANGELOG:?}" "${SCRIPTS:?}" "${GIT_USER:?}" "${GIT_EMAIL:?}" "${VERSION:?}"
DRY_RUN="${DRY_RUN:-false}"
PLGR="python3 $SCRIPTS/plg_release.py"

. "$SCRIPTS/plg_release_git.sh"
plg_git_setup
git fetch --no-tags origin "+refs/heads/$BASE:refs/remotes/origin/$BASE" "+refs/heads/$BETA_BRANCH:refs/remotes/origin/$BETA_BRANCH"
git switch -q -C "$BETA_BRANCH" "origin/$BETA_BRANCH"

if ! git merge --no-ff --no-commit "origin/$BASE" >/dev/null; then
  while IFS= read -r -d '' f; do
    case "$f" in
      "$PLG"|"$CHANGELOG") git checkout "origin/$BETA_BRANCH" -- "$f" ;;
      *) echo "::error::merge conflict in $f — merge $BASE into $BETA_BRANCH by hand"; exit 1 ;;
    esac
  done < <(git diff -z --name-only --diff-filter=U)
fi
git checkout "origin/$BETA_BRANCH" -- "$PLG"
theirs=$(mktemp)
git show "origin/$BASE:$CHANGELOG" > "$theirs"
$PLGR merge-changelog --ours "$CHANGELOG" --theirs "$theirs" --out "$CHANGELOG"
$PLGR render --plg "$PLG" --changelog "$CHANGELOG" --channel beta
$PLGR check --changelog "$CHANGELOG" --plg "$PLG" --channel beta --branch "$BETA_BRANCH"

# --allow-empty: an already-merged base leaves nothing staged, and that is not a failure.
git add "$PLG" "$CHANGELOG"
git commit -q --allow-empty -m "chore(release): merge $BASE into $BETA_BRANCH after $VERSION [skip ci]"

if [ "$DRY_RUN" = true ]; then
  echo "::notice::dry run — would push $BETA_BRANCH"
  git show --stat HEAD
  exit 0
fi
git push -q origin "HEAD:$BETA_BRANCH"
