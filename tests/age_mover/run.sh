#!/bin/bash
# Runs every test_*.sh with debug logging off, then on. Without AGE_MOVER_TEST=1 it starts a container first (CI sets it):
# the tests delete folders under /mnt, so set it only inside a throwaway container.
HERE=$(cd "$(dirname "$0")" && pwd)
if [ "${AGE_MOVER_TEST:-}" != 1 ]; then
    # as CI's container job: PID 1 is tail, which reaps no orphan, so a test that leaves one fails here as it does in CI
    c=$(docker run -d --rm -v "$(cd "$HERE/../.." && pwd):/src:ro" "${AGE_MOVER_IMAGE:-debian:bookworm-slim}" \
        tail -f /dev/null) || exit 2
    trap 'docker rm -f "$c" >/dev/null' EXIT
    docker exec -e AGE_MOVER_TEST=1 "$c" bash /src/tests/age_mover/run.sh
    exit
fi
# packages go in only inside a container: AGE_MOVER_TEST=1 on a host must not change its packages
[ -e /.dockerenv ] || { echo "run.sh: AGE_MOVER_TEST=1 is set outside a container" >&2; exit 2; }
for c in rsync fuser pgrep gawk runuser useradd xmllint; do
    command -v "$c" >/dev/null && continue
    apt-get update -qq && apt-get install -y -qq --no-install-recommends rsync gawk psmisc procps util-linux passwd libxml2-utils >/dev/null || exit 2
    break
done
# Unraid's awk is gawk; Debian's default mawk would test other awk behaviour
awk --version 2>/dev/null | grep -q '^GNU Awk' || { echo "awk is not GNU awk" >&2; exit 2; }
rc=0
for debug in 0 2; do
    for t in "$HERE"/test_*.sh; do
        echo "# $(basename "$t"), debug logging $([ "$debug" = 2 ] && echo on || echo off)"
        AGE_MOVER_DEBUG=$debug bash "$t" || rc=1
    done
done
exit $rc
