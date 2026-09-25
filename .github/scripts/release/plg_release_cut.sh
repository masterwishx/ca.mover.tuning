#!/usr/bin/env bash
# Cut a release on the current channel branch: stamp, render, build, commit, tag, GitHub release, verify.
# Env: CHANNEL BASE STABLE_BRANCH PLG CHANGELOG SCRIPTS PKG_BUILD RELEASE_TITLE GIT_USER GIT_EMAIL TZ DRY_RUN GH_TOKEN [PR_NUMBER]
set -euo pipefail

: "${CHANNEL:?}" "${BASE:?}" "${STABLE_BRANCH:?}" "${PLG:?}" "${CHANGELOG:?}" "${SCRIPTS:?}" "${PKG_BUILD:?}"
: "${RELEASE_TITLE:?}" "${GIT_USER:?}" "${GIT_EMAIL:?}" "${TZ:?}"
DRY_RUN="${DRY_RUN:-false}"
PR_NUMBER="${PR_NUMBER:-}"
PLGR="python3 $SCRIPTS/plg_release.py"

. "$SCRIPTS/plg_release_git.sh"
plg_git_setup
git fetch --tags --force origin
git fetch --no-tags origin "+refs/heads/$STABLE_BRANCH:refs/remotes/origin/$STABLE_BRANCH"

version=$($PLGR next-version --channel "$CHANNEL" --tz "$TZ")
echo "release version: $version"

since=$($PLGR since-ref --changelog "$CHANGELOG" --channel "$CHANNEL")
if [ "$CHANNEL" = stable ]; then
  $PLGR check --changelog "$CHANGELOG" --plg "$PLG" --channel stable --branch "$BASE" --require-nonempty --require-edited --since "$since"
else
  $PLGR check --changelog "$CHANGELOG" --plg "$PLG" --channel beta --branch "$BASE" --require-nonempty
  $PLGR check --changelog "$CHANGELOG" --plg "$PLG" --channel beta --branch "$BASE" --require-edited --since "$since" >/dev/null \
    || echo "::warning::beta notes still contain bullets copied from commit subjects"
fi

beta_flag=()
[ "$CHANNEL" != beta ] || beta_flag=(--beta)
$PLGR stamp --changelog "$CHANGELOG" --version "$version" "${beta_flag[@]}"
$PLGR render --plg "$PLG" --changelog "$CHANGELOG" --channel "$CHANNEL"

rm -rf dist
# The plugin's own build script must not see the release token: strip it from the
# environment and from .git/config for the duration of the build.
plg_git_deauth
env -u GH_TOKEN bash "$PKG_BUILD" --version "$version" --out dist
plg_git_auth
mapfile -t txz < <(find dist -maxdepth 1 -name '*.txz' -type f)
[ "${#txz[@]}" -eq 1 ] || { echo "::error::expected exactly one dist/*.txz, found ${#txz[@]}"; exit 1; }
xmllint --noout "$PLG"
$PLGR check --changelog "$CHANGELOG" --plg "$PLG" --channel "$CHANNEL" --branch "$BASE"

# Each release names the one before it on its channel and how to go back to it: a lower version needs
# "forced", and the install script keeps the settings file (a "major" target also turns test mode on).
rollback_footer() {
  local pre=false prev url cmd info
  [ "$CHANNEL" = stable ] || pre=true
  # a failed lookup must stop the release, not ship it without this note: set -e does not reach into $( )
  prev=$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" \
      --jq '.[] | select((.draft | not) and .prerelease == '"$pre"' and (.tag_name | test("^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}[a-z]?$"))) | .tag_name') \
    || { echo "could not list releases for the rollback note" >&2; return 1; }
  # every page, newest first: a run of betas can push the last stable release past the first
  prev="${prev%%$'\n'*}"
  if [ -n "$prev" ]; then
    # the tag goes into a URL and a pasted root command: only a release version shape may pass
    [[ "$prev" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}[a-z]?$ ]] || { echo "unexpected release tag '$prev'" >&2; return 1; }
    url="https://raw.githubusercontent.com/$GITHUB_REPOSITORY/$prev/$PLG"
    info=$($PLGR verify-manifest --url "$url") || { echo "the rollback note would point at $prev, which no longer installs" >&2; return 1; }
    printf -v cmd 'plugin install %q forced' "$url"
    printf '%s\n' "" "Roll back to [$prev](https://github.com/$GITHUB_REPOSITORY/releases/tag/$prev) if this release causes a problem. Run this in a terminal on the server; your settings are kept:" '```' "$cmd" '```'
    [ "$info" != "upgrade=major" ] || echo "$prev is a major release: installing it turns test mode on, so turn it off again in the Mover Tuning settings afterwards."
  fi
  if [ "$CHANNEL" = beta ]; then
    $PLGR verify-manifest --url "${STABLE_PLUGIN_URL:?}" >/dev/null \
      || { echo "the way back to stable would point at $STABLE_PLUGIN_URL, which does not install" >&2; return 1; }
    printf -v cmd 'plugin install %q forced' "$STABLE_PLUGIN_URL"
    printf '%s\n' "" "To leave the beta and go back to the stable release:" '```' "$cmd" '```'
  elif [ -z "$prev" ]; then
    return 0
  fi
  echo "If Auto Update Applications covers this plugin, turn it off for Mover Tuning until a fix is out, or it will update again."
}

stable_plg=$(mktemp)
git show "origin/$STABLE_BRANCH:$PLG" > "$stable_plg"
STABLE_PLUGIN_URL=$($PLGR entity --plg "$stable_plg" --name pluginURL)
notes=$(mktemp)
plugin_url=$($PLGR entity --plg "$PLG" --name pluginURL)
rollback=$(rollback_footer)
$PLGR notes --changelog "$CHANGELOG" --version "$version" --footer "Install / update URL: \`$plugin_url\`"$'\n'"$rollback" > "$notes"

git add "$PLG" "$CHANGELOG"
git commit -q -m "chore(release): $version [skip ci]"

# Before the dry-run exit: later steps consume this output on both paths.
echo "version=$version" >> "${GITHUB_OUTPUT:-/dev/null}"

if [ "$DRY_RUN" = true ]; then
  echo "::notice::dry run — would push $BASE, tag $version and publish ${txz[0]}"
  git show --stat HEAD
  cat "$notes"
  exit 0
fi

# Publish and verify the package before moving $BASE, so the manifest users fetch only ever
# points at an asset that checked out. A failure in here needs one command to undo; say which.
trap 'echo "::error::$version may be tagged and released while '"$BASE"' is unchanged. Undo with: gh release delete $version --cleanup-tag --yes  (if no release was created, just the tag: git push --delete origin refs/tags/$version)"' ERR

git tag "$version"
git push -q origin "refs/tags/$version"

title="$RELEASE_TITLE $version"
pre=()
[ "$CHANNEL" != beta ] || { title+=" (beta)"; pre=(--prerelease); }
gh release create "$version" "${txz[0]}" --title "$title" --notes-file "$notes" "${pre[@]}"

$PLGR check --changelog "$CHANGELOG" --plg "$PLG" --channel "$CHANNEL" --branch "$BASE" --verify-asset

git push -q origin "HEAD:$BASE"
trap - ERR

# The branch has done its job; left behind, its Unreleased would be carried into the next release PR. Only while it
# is still what was merged: a refresh may have rebuilt it for a new PR since, and deleting it would close that PR.
if [ -n "$PR_NUMBER" ]; then
  { merged_head=$(gh pr view "$PR_NUMBER" --json headRefOid --jq .headRefOid) \
    && git push -q --force-with-lease="refs/heads/release/$CHANNEL:$merged_head" origin ":refs/heads/release/$CHANNEL"; } \
    || echo "::warning::left release/$CHANNEL in place"
fi

# Non-fatal: the release is already published and verified; a failed courtesy comment must not red the run.
if [ -n "$PR_NUMBER" ]; then
  { url=$(gh release view "$version" --json url --jq .url) \
    && gh pr comment "$PR_NUMBER" --body "Released as [$version]($url)." >/dev/null; } \
    || echo "::warning::could not comment on PR #$PR_NUMBER"
fi
