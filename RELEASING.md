# Releasing Mover Tuning

Two channels, one branch each:

| Channel | Branch | Install URL |
|---|---|---|
| Stable | `master` | `https://raw.githubusercontent.com/masterwishx/ca.mover.tuning/master/plugins/ca.mover.tuning.plg` |
| Beta | `beta` | `https://raw.githubusercontent.com/masterwishx/ca.mover.tuning/beta/plugins/ca.mover.tuning.plg` |

New work goes to `beta` through pull requests. Only urgent fixes for the stable release go straight to `master`; they join the next stable release PR.

## How a release happens

The **Release** workflow (`.github/workflows/release.yml`) does all of this; nobody builds packages by hand.

1. A push to `master` or `beta` that changes the plugin opens or updates that channel's release PR, titled `chore(<branch>): release`. It changes only `CHANGELOG.md`: an `## Unreleased` section with one bullet per new commit.
2. Edit that section on the PR branch until it reads the way the release notes should. For a stable release, every bullet copied from a commit subject must be reworded or deleted (a subject ending in a commit hash, for example): the release refuses to go out with one left in. Later pushes add their commits to the PR but keep your edits and deletions. Change only `CHANGELOG.md` there: code fixes go to `master` or `beta` through their own PRs, and a refresh stops (naming the files) rather than drop anything else pushed to the release PR.
3. Merge the PR. The workflow then:
   - picks the version: today's date (UTC), or the date plus `a`, `b`, ... for another release the same day;
   - renames `## Unreleased` to that version and writes the notes into the `.plg` `<CHANGES>`;
   - builds the package, publishes the GitHub release with the package attached, and checks the download matches the `.plg` md5;
   - puts the install URL and the rollback command for the previous release on the release page.
4. After a **beta** release it opens or updates the stable release PR, which brings that beta release into `master` (the release as tagged, not work pushed to `beta` since) with its notes, next to any fixes pushed straight to `master`. Merge that one with a merge commit, not a squash.
5. After a **stable** release it merges `master` back into `beta` and refreshes the beta release PR.

Each branch keeps its own `version`, `md5` and `pluginURL` in the `.plg` (`pluginURL` points at its own branch, so servers on the beta stay on the beta); the rest of the `.plg`, such as the install and remove scripts, merges between the branches like any other file.

## Versions

- The first stable release of a day is the bare date, `2026.09.26`; the next that day is `2026.09.26a`.
- A beta always carries a letter, `2026.09.26a`, `2026.09.26b`, ...
- Unraid compares versions as text, so a stable cut later the same day as a beta (`2026.09.26`) sorts below that beta (`2026.09.26a`). A server moving from that beta back to stable needs `forced`, as the release notes show.

## When something goes wrong

- **The release run failed before publishing** (for example, a bullet was still a commit subject): fix `CHANGELOG.md` on the branch and push. A merged release PR stays due until its release exists, so the next run picks it up, and a push to the other branch starts it too. **Actions > Release > Run workflow** with `mode: release` does the same without a push.
- **It failed after tagging**: the run's error names the one command that undoes it (`gh release delete <version> --cleanup-tag --yes`). Run it, then retry as above.
- **The merge between `master` and `beta` stopped on a conflict** (after a release, or while building the stable release PR): the release itself is out. Merge the branches by hand, keeping the target branch's `version`, `md5` and `pluginURL` in the `.plg`, and push; the next run carries on from there.
- **Dry run**: **Run workflow** with `dry_run` builds and prints everything without pushing, tagging or publishing.

## Setup and upkeep

- `RELEASE_TOKEN` (Settings > Secrets and variables > Actions) is a fine-grained token for this repository with Contents, Pull requests and Workflows set to read and write. The built-in token cannot push the `beta`/`master` merges once a workflow file changes. When it expires, releases stop at the first push; create a new token and replace the secret.
- The workflow pushes release commits straight to `master` and `beta`. A rule that requires pull requests on those branches would block it.
- `archive/` holds the packages of releases up to 2026.09.19. Their `.plg` files download from it, so it stays as it is; newer packages are attached to their GitHub release instead.
- `.github/scripts/release/` holds the release scripts; `ci.yml` runs their tests and checks on every pull request that the committed `.plg` still matches `CHANGELOG.md` and the served package.
