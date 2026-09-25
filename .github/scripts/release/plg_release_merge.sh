#!/usr/bin/env bash
# Sourced, not executed. Merges another ref into HEAD between the channel branches.

# $1 = ref to merge, $2 = the channel of HEAD. The .plg merges three ways, keeping HEAD's version, md5 and
# pluginURL, then CHANGES is rendered for $2; the changelog gains the other side's releases.
plg_merge() {
  local from=$1 channel=$2 base ours theirs theirs_cl
  base=$(mktemp)
  ours=$(mktemp)
  theirs=$(mktemp)
  theirs_cl=$(mktemp)
  git show "$(git merge-base HEAD "$from"):$PLG" > "$base"
  git show "HEAD:$PLG" > "$ours"
  git show "$from:$PLG" > "$theirs"
  git show "$from:$CHANGELOG" > "$theirs_cl"
  if ! git merge --no-ff --no-commit "$from" >/dev/null; then
    while IFS= read -r -d '' f; do
      case "$f" in
        "$PLG"|"$CHANGELOG") ;;
        *) echo "::error::merge conflict in $f — merge $from into $(git rev-parse --abbrev-ref HEAD) by hand"; return 1 ;;
      esac
    done < <(git diff -z --name-only --diff-filter=U)
  fi
  $PLGR merge-manifest --base "$base" --ours "$ours" --theirs "$theirs" --out "$PLG"
  git show "HEAD:$CHANGELOG" > "$CHANGELOG"
  $PLGR merge-changelog --ours "$CHANGELOG" --theirs "$theirs_cl" --out "$CHANGELOG"
  $PLGR render --plg "$PLG" --changelog "$CHANGELOG" --channel "$channel"
  git add "$PLG" "$CHANGELOG"
}
