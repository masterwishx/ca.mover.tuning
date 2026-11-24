#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
HELPER="$ROOT/source/ca.mover.tuning/usr/local/emhttp/plugins/ca.mover.tuning/files_in_use"
MOVER="$ROOT/source/ca.mover.tuning/usr/local/emhttp/plugins/ca.mover.tuning/age_mover"
TMP=$(mktemp -d)
HOLDER=""

cleanup() {
    if [ -n "$HOLDER" ]; then
        kill "$HOLDER" 2>/dev/null || true
        wait "$HOLDER" 2>/dev/null || true
    fi
    rm -rf -- "$TMP"
}
trap cleanup EXIT

expect_status() {
    local expected=$1 actual
    shift
    set +e
    perl "$HELPER" "$@"
    actual=$?
    set -e
    if [ "$actual" -ne "$expected" ]; then
        echo "expected status $expected, got $actual" >&2
        return 1
    fi
}

hold_file() {
    local mode=$1 file=$2 ready="$TMP/ready"
    rm -f -- "$ready"
    if [ "$mode" = read ]; then
        ( exec 9<"$file"; : >"$ready"; sleep 30 ) &
    else
        ( exec 9<>"$file"; : >"$ready"; sleep 30 ) &
    fi
    HOLDER=$!
    for _ in {1..100}; do
        [ -e "$ready" ] && return
        sleep 0.01
    done
    echo "holder did not start" >&2
    return 1
}

release_holder() {
    kill "$HOLDER" 2>/dev/null || true
    wait "$HOLDER" 2>/dev/null || true
    HOLDER=""
}

plain="$TMP/plain"
space="$TMP/a space [*] \$(name)"
newline="$TMP/line
break"
leading="$TMP/--leading"
printf x >"$plain"
printf x >"$space"
printf x >"$newline"
printf x >"$leading"

perl -c "$HELPER"

# F_SETLEASE and fuser -s are Linux interfaces. macOS development machines can
# still validate syntax and the intentionally small age_mover integration.
if [ "$(uname -s)" != Linux ]; then
    grep -q '"${FILES_IN_USE_CMD\[@\]}" "$@"' "$MOVER"
    grep -qE 'FILE_IN_USE_MODE|FILE_IN_USE_CHECK|FUSER_BATCH_SAFE|actionRows' "$MOVER" && exit 1
    grep -qE 'coproc|--server|fileLease(Start|Stop|Request)' "$MOVER" && exit 1
    echo "file lease Linux tests skipped on $(uname -s)"
    exit
fi

expect_status 1 "$plain" "$space" "$newline" "$leading"
expect_status 1 "$TMP/vanished"

hold_file read "$plain"
expect_status 0 "$plain"
release_holder
expect_status 1 "$plain"

hold_file write "$plain"
expect_status 0 "$plain"
release_holder

alias="$TMP/hardlink"
ln "$plain" "$alias"
hold_file read "$alias"
expect_status 0 "$plain" "$alias"
release_holder

# A file that another process holds a lease on is in use, and checking it must not disturb that
# lease: opening it would make the kernel signal the holder to give the lease up.
leased="$TMP/leased"
printf x >"$leased"
rm -f -- "$TMP/ready" "$TMP/broken"
perl -e '
    use Fcntl qw(F_WRLCK);
    my ($file, $ready, $broken) = @ARGV;
    open(my $fh, "<", $file) or die "open: $!";
    $SIG{IO} = sub { open(my $m, ">", $broken); close $m };
    fcntl($fh, 1024, F_WRLCK) or die "lease: $!";
    open(my $r, ">", $ready); close $r;
    sleep 30;
' "$leased" "$TMP/ready" "$TMP/broken" &
HOLDER=$!
for _ in {1..100}; do
    [ -e "$TMP/ready" ] && break
    sleep 0.01
done
[ -e "$TMP/ready" ] || { echo "lease holder did not start" >&2; exit 1; }
grep -q LEASE /proc/locks
expect_status 0 "$leased"
expect_status 0 "$plain" "$leased"
sleep 0.2
if [ -e "$TMP/broken" ]; then
    echo "checking a leased file broke its lease" >&2
    exit 1
fi
release_holder

# A device cannot be leased. A distinctive fake fuser status proves that the
# one-shot helper immediately replaces itself with the compatibility command.
mkdir "$TMP/bin"
printf '#!/bin/sh\nexit 7\n' >"$TMP/bin/fuser"
chmod +x "$TMP/bin/fuser"
set +e
PATH="$TMP/bin:$PATH" perl "$HELPER" /dev/null
fallback_status=$?
set -e
[ "$fallback_status" -eq 7 ]

# If leases cannot answer and fuser cannot be executed, status 2 tells
# age_mover not to mistake the file for clear.
mkdir "$TMP/empty-bin"
set +e
PATH="$TMP/empty-bin" "$(command -v perl)" "$HELPER" /dev/null 2>/dev/null
uncheckable_status=$?
set -e
[ "$uncheckable_status" -eq 2 ]

# Keep age_mover's integration deliberately small: it knows only the helper's
# result contract, not whether a lease or fuser produced the answer.
grep -q '"${FILES_IN_USE_CMD\[@\]}" "$@"' "$MOVER"
grep -qE 'FILE_IN_USE_MODE|FILE_IN_USE_CHECK|FUSER_BATCH_SAFE|actionRows' "$MOVER" && exit 1
grep -qE 'coproc|--server|fileLease(Start|Stop|Request)' "$MOVER" && exit 1

# age_mover treats an unavailable answer as in-use, and reports it only once.
source <(sed -n '/^\(chooseFilesInUseCheck\|filesInUse\)() {/,/^}/p' "$MOVER")
MOVE_IN_USE=no
fake_helper="$TMP/fake-helper"
# age_mover runs the helper through perl
printf 'exit $ENV{CHECK_STATUS};\n' >"$fake_helper"
chmod +x "$fake_helper"
# Read by the sourced filesInUse, which ShellCheck cannot see.
# shellcheck disable=SC2034
FILES_IN_USE_HELPER=$fake_helper
LOG_COUNT=0
mvlogger() { LOG_COUNT=$((LOG_COUNT + 1)); }
# Stands in for processTheMoves, which owns the once-per-run flag as a local.
mover_run() {
    local FILE_IN_USE_FAILURE_LOGGED=no
    local -a FILES_IN_USE_CMD=()
    chooseFilesInUseCheck
    export CHECK_STATUS=0
    filesInUse "$plain"
    export CHECK_STATUS=1
    if filesInUse "$plain"; then
        echo "clear helper result was reported in use" >&2
        exit 1
    fi
    export CHECK_STATUS=2
    filesInUse "$plain"
    filesInUse "$plain"
}
mover_run
[ "$LOG_COUNT" -eq 1 ]
# The next run warns again, and the flag does not leak out of the run.
mover_run
[ "$LOG_COUNT" -eq 2 ]
[ -z "${FILE_IN_USE_FAILURE_LOGGED+set}" ]
[ -z "${FILES_IN_USE_CMD+set}" ]

# Without Perl, as before Unraid 6.11.0, age_mover runs fuser -s itself, and says so once per run.
old_run() {
    local FILE_IN_USE_FAILURE_LOGGED=no
    local -a FILES_IN_USE_CMD=()
    chooseFilesInUseCheck
    [ "${FILES_IN_USE_CMD[*]}" = "fuser -s" ]
    export FUSER_STATUS=0
    filesInUse "$plain"
    export FUSER_STATUS=1
    if filesInUse "$plain"; then
        echo "clear fuser result was reported in use" >&2
        exit 1
    fi
}
printf '#!/bin/sh\n[ "$1" = -s ] || exit 9\nexit "$FUSER_STATUS"\n' >"$TMP/bin/fuser"
LOG_COUNT=0
PATH="$TMP/bin" old_run
[ "$LOG_COUNT" -eq 1 ]
# Without fuser either, the file stays put and the unchecked-file warning follows the fuser one.
no_fuser_run() {
    local FILE_IN_USE_FAILURE_LOGGED=no
    local -a FILES_IN_USE_CMD=()
    PATH="$TMP/empty-bin" chooseFilesInUseCheck
    PATH="$TMP/empty-bin" filesInUse "$plain"
    PATH="$TMP/empty-bin" filesInUse "$plain"
}
LOG_COUNT=0
no_fuser_run
[ "$LOG_COUNT" -eq 2 ]
# With "Move files that are in use" on, nothing is checked, so the fuser note is not logged.
# shellcheck disable=SC2034 # read by the sourced chooseFilesInUseCheck
MOVE_IN_USE=yes
LOG_COUNT=0
PATH="$TMP/empty-bin" chooseFilesInUseCheck
[ "$LOG_COUNT" -eq 0 ]
# With Perl in PATH, wherever it is, the helper runs through it.
mkdir "$TMP/perl-bin"
ln -s "$(command -v perl)" "$TMP/perl-bin/perl"
PATH="$TMP/perl-bin" chooseFilesInUseCheck
[ "${FILES_IN_USE_CMD[*]}" = "perl $FILES_IN_USE_HELPER" ]

echo "file lease tests passed"
