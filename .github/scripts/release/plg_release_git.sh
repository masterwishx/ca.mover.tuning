#!/usr/bin/env bash
# Sourced, not executed. The plugin repo checks out with persist-credentials: false;
# these attach the token to origin only around the pushes, never across the build.

# Identity plus an authenticated origin. Outside Actions (no token) the remote is left alone.
plg_git_setup() {
    git config user.name "${GIT_USER:?}"
    git config user.email "${GIT_EMAIL:?}"
    plg_git_auth
}

plg_git_auth() {
    [ -n "${GH_TOKEN:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ] || return 0
    git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
}

# Call before handing control to a build command; pair it with plg_git_auth afterwards.
plg_git_deauth() {
    [ -n "${GITHUB_REPOSITORY:-}" ] || return 0
    git remote set-url origin "https://github.com/${GITHUB_REPOSITORY}.git"
}
