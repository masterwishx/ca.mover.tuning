#!/bin/bash
# Sourced by test_*.sh: each case runs the real processTheMoves with real rsync and the shipped default.cfg read by the real
# getMoverSettings; Unraid's move is a stand-in. It deletes /mnt/cache, /mnt/user0 and /mnt/other.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN=$HERE/../../source/ca.mover.tuning/usr/local/emhttp/plugins/ca.mover.tuning
AM=${AM:-$PLUGIN/age_mover}
T=/tmp/age_mover_test

# a bind mount at or above one of these would put the host's files under the wipe
same_fs_as_root() {
    local d
    for d in /mnt /mnt/cache /mnt/user0 /mnt/other; do
        [ ! -e "$d" ] || [ "$(stat -c %d "$d")" = "$(stat -c %d /)" ] || return 1
    done
}
if [ "${AGE_MOVER_TEST:-}" != 1 ] || [ ! -e /.dockerenv ] || ! same_fs_as_root; then
    echo "lib.sh deletes /mnt/cache, /mnt/user0 and /mnt/other: start the tests with tests/age_mover/run.sh" >&2
    exit 2
fi

mkdir -p "$T/bin" "$T/cwd" /usr/libexec/unraid
cat >/usr/libexec/unraid/move <<'EOF'
#!/bin/bash
# stand-in for Unraid's move: a name on the cache goes to the array (/mnt/user0), a name anywhere else goes to the cache
while IFS= read -r p; do
    [ -n "$p" ] || continue
    root=${p#/mnt/} root=${root%%/*}
    rel=${p#/mnt/"$root"/} to=/mnt/cache
    [ "$root" = cache ] && to=/mnt/user0
    mkdir -p "$to/${rel%/*}"
    if [ -d "$p" ] && [ ! -L "$p" ]; then
        mkdir -p "$to/$rel" && rmdir "$p" 2>/dev/null
    else
        mv -- "$p" "$to/$rel"
    fi && echo "move: $p Success"
done
EOF
chmod 755 /usr/libexec/unraid/move
PATH=$T/bin:$PATH

# age_mover runs its command on load, so only its functions and its top-level counters are taken
awk '/^[A-Za-z_][A-Za-z0-9_]*\(\) \{/,/^\}/' "$AM" >"$T/funcs.sh"
. "$T/funcs.sh"
grep -E '^[A-Z_]+=(-?[0-9]+|"")$' "$AM" >"$T/globals.sh"
if ! declare -F processTheMoves getMoverSettings >/dev/null; then
    echo "lib.sh: processTheMoves or getMoverSettings did not load from $AM" >&2
    exit 2
fi
LOGLEVEL=1 IS_CRON=1 DEBUGLEVEL=${AGE_MOVER_DEBUG:-0} LOGFOLDER=$T MOVER_LOG=$T/log MOVER_DEBUG_LOG=$T/dlog
MOVER_STATUS=$T/mover.ini STATS_FILE=$T/stats MOVER_ACTIONLIST=$T/actions SOFTSTOPFILE=$T/softstop SOFTSTOP_ACK=false
PAUSEFILE=$T/pause MOVINGFILE=$T/moving PIDFILE=$T/pid MOVERTUNINGCFGFILE=$T/cfg MOVERTUNING_OVERRIDE_CFGFOLDER=$T/overrides
MOVERTUNING_DEFAULT_CFGFILE=$PLUGIN/default.cfg NOW=2026-01-02T030405 UNRAID_VERSION=7.2.0
HDR='PRIMARYSTORAGENAME|SHARENAME|SHAREUSECACHE|MODIFYTIME|FILESIZE|POOLSUM|THRESHOLD|PROJECTED|NBLINKS|INODE|ACTION|FROM|TO|FILETYPE|FILEPATH'
FAILS=0 CHECKS=0

# setting [key value]...: the shipped defaults with these keys changed, as getMoverSettings reads them
setting() {
    cp "$PLUGIN/default.cfg" "$T/cfg"
    while [ $# -ge 2 ]; do
        grep -q "^$1=" "$T/cfg" || { echo "setting: $1 is not in default.cfg" >&2; exit 2; }
        sed -i "s|^$1=.*|$1=\"$2\"|" "$T/cfg"
        shift 2
    done
    getMoverSettings "$T/cfg" >/dev/null 2>&1
    MOVER_PROGRESS=yes
}

# begin <case> [key value]...: empty cache, array and other pool, and the case's settings
begin() {
    CASE=$1
    shift
    rm -rf /mnt/cache /mnt/user0 /mnt/other "$SOFTSTOPFILE" "$PAUSEFILE" "$T/after_rsync" "$T/bin/rsync"
    mkdir -p /mnt/cache /mnt/user0
    setting "$@"
}

# mk <root> <share/path>...: a 2-byte file at /mnt/<root>/<path>
mk() {
    local r=$1 p
    shift
    for p; do
        mkdir -p "/mnt/$r/${p%/*}" && printf 'x\n' >"/mnt/$r/$p"
    done
}

# row <action> <type> <share/path> [links inode mtime]: the planner's row for the name, stat'd where it is now
row() {
    local from to p m i n s
    case "$1" in
    "keep on primary") from=/mnt/cache to=none ;;
    *"from primary" | "sync unattended to secondary") from=/mnt/cache to=/mnt/user0 ;;
    *"from secondary") from=/mnt/user0 to=/mnt/cache ;;
    "move unattended to primary") from=/mnt/other to=/mnt/cache ;;
    *) from=/mnt/other to=/mnt/user0 ;;
    esac
    for p in "$from/$3" "/mnt/other/$3"; do [ -e "$p" ] && break; done
    read -r m i n s < <(stat -c '%Y %i %h %s' "$p")
    printf 'cache|%s|yes|%s|%s|0|0|0|%s|%s|%s|%s|%s|%s|%s\n' "${3%%/*}" "${6:-$m}" "$s" "${4:-$n}" "${5:-$i}" "$1" "$from" "$to" "$2" "$3"
}

list() { { echo "$HDR"; cat; } >"$MOVER_ACTIONLIST"; }

# after_first_rsync <command>: runs the command once, right after the pass's first rsync call ends
after_first_rsync() {
    printf '%s\n' "$1" >"$T/after_rsync"
    printf '#!/bin/bash\n%q "$@"\nrc=$?\n[ -e %q ] && { bash %q; rm -f %q; }\nexit $rc\n' \
        "$(PATH=${PATH#"$T/bin:"} command -v rsync)" "$T/after_rsync" "$T/after_rsync" "$T/after_rsync" >"$T/bin/rsync"
    chmod 755 "$T/bin/rsync"
}

# the totals the planner counts per direction; a staged move to the primary is counted by its sync row
run_moves() {
    . "$T/globals.sh"
    read -r TOTALPRIMARYFILES TOTALPRIMARYFOLDERS TOTALPRIMARYSIZE TOTALSECONDARYFILES TOTALSECONDARYFOLDERS TOTALSECONDARYSIZE \
        TOTALUNATTENDEDFILES TOTALUNATTENDEDFOLDERS TOTALUNATTENDEDSIZE < <(awk -F'|' '
        NR == FNR { if ($11 == "sync unattended to secondary") staged[$15] = 1; next }
        FNR == 1 { next }
        { d = "" }
        $11 == "move from primary" || $11 == "sync from primary" { d = "p" }
        $11 == "move from secondary" || $11 == "sync from secondary" { d = "s" }
        $11 ~ /unattended/ && !($11 == "move unattended to primary" && ($15 in staged)) { d = "u" }
        d != "" { n[d ($14 == "d" ? "d" : "f")]++; sz[d] += $5 }
        END { print n["pf"] + 0, n["pd"] + 0, sz["p"] + 0, n["sf"] + 0, n["sd"] + 0, sz["s"] + 0, n["uf"] + 0, n["ud"] + 0, sz["u"] + 0 }
    ' "$MOVER_ACTIONLIST" "$MOVER_ACTIONLIST")
    TOTALFILES=$((TOTALPRIMARYFILES + TOTALSECONDARYFILES + TOTALUNATTENDEDFILES))
    TOTALFOLDERS=$((TOTALPRIMARYFOLDERS + TOTALSECONDARYFOLDERS + TOTALUNATTENDEDFOLDERS))
    START_TIME=$EPOCHSECONDS
    : >"$MOVER_LOG"
    : >"$MOVER_DEBUG_LOG"
    (
        cd "$T/cwd" || exit
        processTheMoves
        for v in MOVEDFILES MOVEDFOLDERS NOTMOVEDFILES NOTMOVEDFOLDERS VANISHEDFILES VANISHEDFOLDERS INUSEFILES \
            REMAINING_CACHE_FILES REMAINING_CACHE_FOLDERS REMAINING_ARRAY_FILES REMAINING_UNATTENDED_FILES; do
            echo "$v=${!v}"
        done >"$T/counters"
    ) >"$T/out" 2>"$T/err"
    . "$T/counters"
}

check() { # check <what> <expected> <got>
    CHECKS=$((CHECKS + 1))
    if [ "$2" = "$3" ]; then
        echo "ok - $CASE: $1"
    else
        FAILS=$((FAILS + 1))
        echo "not ok - $CASE: $1"
        printf '%s\n' "  expected:" "${2:-(nothing)}" "  got:" "${3:-(nothing)}" | sed 's/^/    /'
    fi
}
tree() { (cd "/mnt/$1" 2>/dev/null && find . -mindepth 1 | sed 's|^\./||' | LC_ALL=C sort); }
# cache_is / array_is [path]...: exactly these names under /mnt/cache or /mnt/user0, nothing else
cache_is() { check "cache holds exactly${*:+ $*}" "$( (($#)) && printf '%s\n' "$@" | LC_ALL=C sort)" "$(tree cache)"; }
array_is() { check "array holds exactly${*:+ $*}" "$( (($#)) && printf '%s\n' "$@" | LC_ALL=C sort)" "$(tree user0)"; }
links() { check "$2 on the array has $1 links" "$1" "$(stat -c %h "/mnt/user0/$2" 2>&1)"; }
counter() { check "$1 is $2" "$2" "${!1}"; }
log() { sed -E 's/^[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3} //' "$MOVER_LOG"; }
log_has() { check "log has: $1" 1 "$(log | grep -cF -- "$1" | sed 's/^[1-9][0-9]*$/1/')"; }
log_lacks() { check "log lacks: $1" 0 "$(log | grep -cF -- "$1")"; }
log_count() { check "log has $1 lines with: $2" "$1" "$(log | grep -cF -- "$2")"; }

finish() {
    echo "# $(basename "$0"): $((CHECKS - FAILS)) of $CHECKS checks passed"
    [ "$FAILS" = 0 ]
}
