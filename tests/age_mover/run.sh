#!/bin/bash
# Runs every test_*.sh with debug logging off, then on. Without AGE_MOVER_TEST=1 it starts a container first (CI sets it):
# the tests delete /mnt/cache, /mnt/user0 and /mnt/other, so set it only inside a throwaway container.
HERE=$(cd "$(dirname "$0")" && pwd)
if [ "${AGE_MOVER_TEST:-}" != 1 ]; then
    exec docker run --rm --init -e AGE_MOVER_TEST=1 -v "$(cd "$HERE/../.." && pwd):/src:ro" \
        "${AGE_MOVER_IMAGE:-debian:bookworm-slim}" bash /src/tests/age_mover/run.sh
fi
for c in rsync fuser pgrep gawk runuser; do
    command -v "$c" >/dev/null && continue
    apt-get update -qq && apt-get install -y -qq --no-install-recommends rsync gawk psmisc procps util-linux >/dev/null || exit 2
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
