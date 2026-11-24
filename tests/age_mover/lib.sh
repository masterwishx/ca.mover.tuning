#!/bin/bash
# shellcheck disable=SC2034 # the settings set here are read by age_mover's functions, sourced from funcs.sh
# Sourced by test_*.sh: each age_mover case runs the real processTheMoves with real rsync and the shipped default.cfg read by the real
# getMoverSettings; Unraid's move and notify, findmnt, zfs, mount and umount are stand-ins. It deletes the folders in ROOTS.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN=$HERE/../../source/ca.mover.tuning/usr/local/emhttp/plugins/ca.mover.tuning
AM=${AM:-$PLUGIN/age_mover}
T=${T:-/tmp/age_mover_test} # test_folders.sh runs its plain-user half with its own T
ROOTS=(/mnt/cache /mnt/user0 /mnt/disk1 /mnt/disk2 /mnt/other)

# a mount at or under /mnt would put the host's files under the wipe, and one at a stand-in's path or above it the
# host's own under the stand-in; an unreadable mount table refuses too
no_host_mount() {
    awk '$5 == "/mnt" || index($5, "/mnt/") == 1 || $5 ~ "^/usr(/libexec(/unraid(/move)?)?)?$" ||
        $5 ~ "^/usr/local(/emhttp(/webGui(/scripts(/notify)?)?)?)?$" { exit 1 }' /proc/self/mountinfo
}
if [ "${AGE_MOVER_TEST:-}" != 1 ] || [ ! -e /.dockerenv ] || ! no_host_mount; then
    echo "lib.sh deletes ${ROOTS[*]} and writes /usr/libexec/unraid/move and /usr/local/emhttp/webGui/scripts/notify: start" \
        "the tests with tests/age_mover/run.sh" >&2
    exit 2
fi

mkdir -p "$T/cwd" "$T/bin"
# root installs the move stand-in; the plain-user run uses the one root installed before it
if [ "$(id -u)" = 0 ]; then
    mkdir -p /usr/libexec/unraid
    cat >/usr/libexec/unraid/move <<'EOF'
#!/bin/bash
# stand-in for Unraid's move: a name on the cache goes to the array (/mnt/user0), a name anywhere else to the cache.
# A file is copied, as across disks, so names of one inode stay linked only when they come in the same run.
declare -A linked
while IFS= read -r p; do
    [ -n "$p" ] || continue
    root=${p#/mnt/} root=${root%%/*}
    rel=${p#/mnt/"$root"/} to=/mnt/cache
    [ "$root" = cache ] && to=/mnt/user0
    mkdir -p "$to/${rel%/*}"
    if [ -d "$p" ] && [ ! -L "$p" ]; then
        mkdir -p "$to/$rel" && rmdir "$p" 2>/dev/null
    else
        i=$(stat -c %i "$p")
        if [ -n "${linked[$i]}" ]; then ln -- "${linked[$i]}" "$to/$rel"; else cp -a -- "$p" "$to/$rel"; fi && rm -- "$p" && linked[$i]=$to/$rel
    fi && echo "move: $p Success"
done
EOF
    chmod 755 /usr/libexec/unraid/move
    mkdir -p /usr/local/emhttp/webGui/scripts
    cat >/usr/local/emhttp/webGui/scripts/notify <<'EOF'
#!/bin/bash
# stand-in for Unraid's notify: each notice's importance and description, as one line in $NOTIFY_LOG
while getopts 's:d:i:l:' o; do
    case $o in d) desc=$OPTARG ;; i) imp=$OPTARG ;; s | l) ;; *) exit 1 ;; esac
done
printf '%s|%s\n' "$imp" "$desc" >>"${NOTIFY_LOG:?}"
EOF
    chmod 755 /usr/local/emhttp/webGui/scripts/notify
fi
# a path in $T/zfs is a ZFS mountpoint (a tab, then its dataset, else the path less /mnt/); zfs logs calls to $T/zfs.calls
# and fails unanswered calls and each subcommand in $T/zfs.fail, with $T/zfs.reason (else zfs.fail) then a child's name
cat >"$T/bin/findmnt" <<'EOF'
#!/bin/bash
l=$(awk -F'\t' -v p="${*: -1}" '$1 == p {print; exit}' "${0%/bin/findmnt}/zfs" 2>/dev/null)
[ -n "$l" ] || exit 0
case "$2" in
source) n=${l#*$'\t'}; [ "$n" != "$l" ] || n=${l#/mnt/}; echo "$n" ;;
*) echo zfs ;;
esac
EOF
cat >"$T/bin/zfs" <<'EOF'
#!/bin/bash
d=${0%/bin/zfs}
n=${*: -1}
echo "zfs $*" >>"$d/zfs.calls"
# $T/zfs.on_<subcommand> runs first, as a write while zfs works
[ ! -f "$d/zfs.on_$1" ] || bash "$d/zfs.on_$1"
if grep -qxF -- "$1" "$d/zfs.fail" 2>/dev/null; then
    r=$(cat "$d/zfs.reason" 2>/dev/null) || r=zfs.fail
    printf "cannot %s '%s': %s\n%s/child\n" "$1" "$n" "$r" "$n" >&2
    exit 1
fi
# the line of file $1 for dataset $n
entry() { awk -F'\t' -v n="$n" '(NF > 1 ? $2 : substr($1, 6)) == n' "$1" 2>/dev/null; }
case "$*" in
# $T/zfs.children holds the children and snapshots
"list -r -H -t filesystem,volume,snapshot -o name "*)
    echo "$n"; cat "$d/zfs.children" 2>/dev/null || :
    ;;
# unmount unlists the dataset and hides its files, keeping its folder; mount lists it and brings them back, hiding,
# as an overlay mount does, what the folder gained meanwhile, and fails while mount has it at a private folder
"unmount "*)
    l=$(entry "$d/zfs")
    [ -n "$l" ] || { echo "cannot unmount '$n': not currently mounted" >&2; exit 1; }
    echo "$l" >>"$d/zfs.off"
    grep -vxF -- "$l" "$d/zfs" >"$d/zfs.new"; mv "$d/zfs.new" "$d/zfs"
    mkdir -p "$d/zfs.store/$n" && find "${l%%$'\t'*}" -mindepth 1 -maxdepth 1 -exec mv -t "$d/zfs.store/$n" {} +
    ;;
"mount "*)
    [ -z "$(awk -F'\t' -v n="$n" '$2 == n' "$d/zfs.private" 2>/dev/null)" ] ||
        { echo "cannot mount '$n': filesystem already mounted" >&2; exit 1; }
    l=$(entry "$d/zfs.off" | tail -n 1) && f=${l%%$'\t'*}
    mkdir -p "$d/zfs.hidden" "$f" && find "$f" -mindepth 1 -maxdepth 1 -exec mv -t "$d/zfs.hidden" {} +
    find "$d/zfs.store/$n" -mindepth 1 -maxdepth 1 -exec mv -t "$f" {} +
    echo "$l" >>"$d/zfs"
    ;;
# the dataset's files go with it, and OpenZFS removes an inherited mountpoint
"destroy "*) rm -rf -- "$(entry "$d/zfs.off" | tail -n 1 | cut -f1)" "$d/zfs.store/$n" ;;
*) echo "zfs stand-in has no answer for: zfs $*" >&2; exit 1 ;;
esac
EOF
# mount -t zfs -o ro,zfsutil DATASET DIR moves an unmounted dataset's files into an empty DIR outside /mnt, umount back; both
# log to zfs.calls with a mktemp DIR as PRIVATE, run zfs.on_mount.zfs or zfs.on_umount, and fail on mount.zfs or umount
cat >"$T/bin/mount" <<'EOF'
#!/bin/bash
d=${0%/bin/mount}
p=${*: -1}
[[ $p == "${TMPDIR:-/tmp}"/ca.mover.tuning.?????? ]] && shown=PRIVATE || shown=$p
echo "mount ${*:1:$#-1} $shown" >>"$d/zfs.calls"
[ ! -f "$d/zfs.on_mount.zfs" ] || bash "$d/zfs.on_mount.zfs"
[ $# = 6 ] && [ "$1 $2 $3 $4" = "-t zfs -o ro,zfsutil" ] || { echo "mount stand-in has no answer for: mount $*" >&2; exit 1; }
n=$5
if grep -qxF mount.zfs "$d/zfs.fail" 2>/dev/null; then
    r=$(cat "$d/zfs.reason" 2>/dev/null) || r=zfs.fail
    echo "filesystem '$n' cannot be mounted, $r" >&2
    exit 1
fi
case $p in /mnt | /mnt/*) echo "mount stand-in: $p is under /mnt" >&2; exit 1 ;; esac
[ -d "$p" ] && [ -z "$(find "$p" -mindepth 1 -print -quit)" ] || { echo "mount stand-in: $p is not an empty folder" >&2; exit 1; }
if [ ! -d "$d/zfs.store/$n" ] || [ -n "$(awk -F'\t' -v n="$n" '$2 == n' "$d/zfs.private" 2>/dev/null)" ] ||
    [ -n "$(awk -F'\t' -v n="$n" '(NF > 1 ? $2 : substr($1, 6)) == n' "$d/zfs" 2>/dev/null)" ]; then
    echo "filesystem '$n' is already mounted" >&2
    exit 1
fi
find "$d/zfs.store/$n" -mindepth 1 -maxdepth 1 -exec mv -t "$p" {} +
printf '%s\t%s\n' "$p" "$n" >>"$d/zfs.private"
EOF
cat >"$T/bin/umount" <<'EOF'
#!/bin/bash
d=${0%/bin/umount}
p=$1
l=$(awk -F'\t' -v p="$p" '$1 == p' "$d/zfs.private" 2>/dev/null)
[ -n "$l" ] && shown=PRIVATE || shown=$p
echo "umount $shown" >>"$d/zfs.calls"
[ ! -f "$d/zfs.on_umount" ] || bash "$d/zfs.on_umount"
[ $# = 1 ] || { echo "umount stand-in has no answer for: umount $*" >&2; exit 1; }
if grep -qxF umount "$d/zfs.fail" 2>/dev/null; then
    r=$(cat "$d/zfs.reason" 2>/dev/null) || r=zfs.fail
    echo "umount: $p: $r" >&2
    exit 32
fi
[ -n "$l" ] || { echo "umount: $p: not mounted." >&2; exit 32; }
find "$p" -mindepth 1 -maxdepth 1 -exec mv -t "$d/zfs.store/${l#*$'\t'}" {} +
grep -vxF -- "$l" "$d/zfs.private" >"$d/zfs.new"
mv "$d/zfs.new" "$d/zfs.private"
EOF
# as Linux does, rmdir refuses a folder something is mounted on
cat >"$T/bin/rmdir" <<'EOF'
#!/bin/bash
if [ -n "$(awk -F'\t' -v p="${*: -1}" '$1 == p' "${0%/bin/rmdir}/zfs.private" 2>/dev/null)" ]; then
    echo "rmdir: failed to remove '${*: -1}': Device or resource busy" >&2
    exit 1
fi
exec /bin/rmdir "$@"
EOF
chmod 755 "$T/bin/findmnt" "$T/bin/zfs" "$T/bin/mount" "$T/bin/umount" "$T/bin/rmdir"
PATH=$T/bin:$PATH
export NOTIFY_LOG=$T/notify

# age_mover runs its command on load, so only its functions and its top-level start values are taken
awk '/^[A-Za-z_][A-Za-z0-9_]*\(\) \{/,/^\}/' "$AM" >"$T/funcs.sh"
. "$T/funcs.sh"
grep -E '^[A-Z_]+=(-?[0-9]+|"")$' "$AM" >"$T/globals.sh"
if ! declare -F processTheMoves getMoverSettings >/dev/null; then
    echo "lib.sh: processTheMoves or getMoverSettings did not load from $AM" >&2
    exit 2
fi
LOGFOLDER=$T MOVER_LOG=$T/log MOVER_DEBUG_LOG=$T/dlog
MOVER_STATUS=$T/mover.ini STATS_FILE=$T/stats MOVER_ACTIONLIST=$T/actions SOFTSTOPFILE=$T/softstop SOFTSTOP_ACK=false
PAUSEFILE=$T/pause MOVINGFILE=$T/moving PIDFILE=$T/pid MOVERTUNINGCFGFILE=$T/cfg MOVERTUNING_OVERRIDE_CFGFOLDER=$T/overrides
MOVERTUNING_DEFAULT_CFGFILE=$PLUGIN/default.cfg FILES_IN_USE_HELPER=$PLUGIN/files_in_use NOW=2026-01-02T030405 UNRAID_VERSION=7.2.0
export TZ=UTC # NOW turns into the sync date in local time
DEBUGLOGGING=no
[ "${AGE_MOVER_DEBUG:-0}" != 2 ] || DEBUGLOGGING=fileOnly
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
    getMoverSettings "$T/cfg" >/dev/null 2>&1 || { echo "setting: getMoverSettings failed on $T/cfg" >&2; exit 2; }
    MOVER_PROGRESS=yes
}

# fresh [key value]...: age_mover's start values and the case's settings, on the folders as they are
fresh() {
    . "$T/globals.sh"
    IS_CRON=1 # after the start values: as under cron, nothing goes to syslog
    setting debuglogging "$DEBUGLOGGING" "$@"
}

# begin <case> [key value]...: empty pools and disks, then fresh
begin() {
    CASE=$1
    shift
    rm -rf "${ROOTS[@]}" "$SOFTSTOPFILE" "$PAUSEFILE" "$T/row_error" "$T/zfs" "$T/zfs".* "$T/after_rsync" "$T/bin/rsync" \
        "$MOVER_LOG" "$NOTIFY_LOG" "${TMPDIR:-/tmp}"/ca.mover.tuning.*
    mkdir -p /mnt/cache /mnt/user0
    fresh "$@"
}

# after_first_rsync <command>: runs the command once, right after the case's first rsync ends; its errors go to the stderr
# run_moves checks. The wrapper renames its process, or copyPids would take it for the copy
after_first_rsync() {
    local h=$T/after_rsync e=$T/row_error
    printf '%s\n' "$1" >"$h"
    # shellcheck disable=SC2016 # the wrapper expands its own $$, $@ and $?
    printf '#!/bin/bash\nprintf hook >/proc/$$/comm\n%q "$@"\nrc=$?\n[ -e %q ] && { bash %q 2>>%q || echo "after_first_rsync: the command failed" >>%q; rm -f %q; }\nexit $rc\n' \
        "$(PATH=${PATH#"$T/bin:"} command -v rsync)" "$h" "$h" "$e" "$e" "$h" >"$T/bin/rsync"
    chmod 755 "$T/bin/rsync"
}

# mk <root> <share/path>...: a 2-byte file at /mnt/<root>/<path>
mk() {
    local r=$1 p
    shift
    for p; do
        mkdir -p "/mnt/$r/${p%/*}" && printf 'x\n' >"/mnt/$r/$p"
    done
}

# row <action> <type> <share/path> [links inode mtime]: the planner's row for the name, stat'd where it is now; the
# planner reads the array by disk, so a row from the secondary comes from /mnt/disk1 or /mnt/disk2
row() {
    local from to p m i n s
    case "$1" in
    "keep on primary") from=/mnt/cache to=none ;;
    *"from primary" | "sync unattended to secondary") from=/mnt/cache to=/mnt/user0 ;;
    *"from secondary") from=/mnt/disk1 to=/mnt/cache; [ -e "/mnt/disk2/$3" ] && from=/mnt/disk2 ;;
    "move unattended to primary") from=/mnt/other to=/mnt/cache ;;
    *) from=/mnt/other to=/mnt/user0 ;;
    esac
    for p in "$from/$3" "/mnt/other/$3" ""; do [ -e "$p" ] && break; done
    [ -n "$p" ] || { echo "row: no $3 under $from or /mnt/other" | tee -a "$T/row_error" >&2; return 1; }
    read -r m i n s < <(stat -c '%Y %i %h %s' "$p")
    printf 'cache|%s|yes|%s|%s|0|0|0|%s|%s|%s|%s|%s|%s|%s\n' "${3%%/*}" "${6:-$m}" "$s" "${4:-$n}" "${5:-$i}" "$1" "$from" "$to" "$2" "$3"
}

# list: the rows on stdin as the action list; as in the planner, a hardlink group's size counts on its first name only
list() { { echo "$HDR"; awk -F'|' -v OFS='|' '$9 > 1 && seen[$12 "|" $9 "|" $10 "|" $4]++ { $5 = 0 } 1'; } >"$MOVER_ACTIONLIST"; }

# run_moves [stderr]: processTheMoves after the totals the planner counts per direction (a staged move to the primary is
# counted by its sync row); stderr must be exactly the given text, nothing by default
run_moves() {
    read -r TOTALPRIMARYFILES TOTALPRIMARYFOLDERS TOTALPRIMARYSIZE TOTALSECONDARYFILES TOTALSECONDARYFOLDERS TOTALSECONDARYSIZE \
        TOTALUNATTENDEDFILES TOTALUNATTENDEDFOLDERS TOTALUNATTENDEDSIZE < <(awk -F'|' '
        function path(  p, i) { p = $15; for (i = 16; i <= NF; i++) p = p "|" $i; return p }
        NR == FNR { if ($11 == "sync unattended to secondary") staged[path()] = 1; next }
        FNR == 1 { next }
        { d = "" }
        $11 == "move from primary" || $11 == "sync from primary" { d = "p" }
        $11 == "move from secondary" || $11 == "sync from secondary" { d = "s" }
        $11 ~ /unattended/ && !($11 == "move unattended to primary" && (path() in staged)) { d = "u" }
        d != "" { n[d ($14 == "d" ? "d" : "f")]++; sz[d] += $5 }
        END { print n["pf"] + 0, n["pd"] + 0, sz["p"] + 0, n["sf"] + 0, n["sd"] + 0, sz["s"] + 0, n["uf"] + 0, n["ud"] + 0, sz["u"] + 0 }
    ' "$MOVER_ACTIONLIST" "$MOVER_ACTIONLIST")
    TOTALFILES=$((TOTALPRIMARYFILES + TOTALSECONDARYFILES + TOTALUNATTENDEDFILES))
    TOTALFOLDERS=$((TOTALPRIMARYFOLDERS + TOTALSECONDARYFOLDERS + TOTALUNATTENDEDFOLDERS))
    START_TIME=$EPOCHSECONDS
    : >"$MOVER_LOG"
    : >"$MOVER_DEBUG_LOG"
    rm -f "$T/counters"
    (
        cd "$T/cwd" || exit
        processTheMoves
        while IFS='=' read -r v _; do printf '%s=%q\n' "$v" "${!v}"; done <"$T/globals.sh" >"$T/counters"
    ) >"$T/out" 2>"$T/err"
    check "the rows were built and processTheMoves returned with $([ -n "${1:-}" ] && echo the expected text || echo nothing) on stderr" "${1:-}" \
        "$(cat "$T/row_error" "$T/err" 2>/dev/null; [ -f "$T/counters" ] || echo "processTheMoves did not return")"
    [ ! -f "$T/counters" ] || . "$T/counters"
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
# holds <root> [path]...: exactly these names under /mnt/<root>, nothing else
holds() { local r=$1; shift; check "$r holds exactly${*:+ $*}" "$( (($#)) && printf '%s\n' "$@" | LC_ALL=C sort)" "$(tree "$r")"; }
cache_is() { holds cache "$@"; }
array_is() { holds user0 "$@"; }
links() { check "$2 on the array has $1 links" "$1" "$(stat -c %h "/mnt/user0/$2" 2>&1)"; }
counter() { check "$1 is $2" "$2" "${!1}"; }
log() { sed -E 's/^[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3} //' "$MOVER_LOG"; }
log_has() { check "log has: $1" 1 "$(log | grep -cF -- "$1" | sed 's/^[1-9][0-9]*$/1/')"; }
log_lacks() { check "log lacks: $1" 0 "$(log | grep -cF -- "$1")"; }
log_count() { check "log has $1 lines with: $2" "$1" "$(log | grep -cF -- "$2")"; }
dlog_has() { check "debug log has: $1" 1 "$(grep -cF -- "$1" "$MOVER_DEBUG_LOG" | sed 's/^[1-9][0-9]*$/1/')"; }
dlog_lacks() { check "debug log lacks: $1" 0 "$(grep -cF -- "$1" "$MOVER_DEBUG_LOG")"; }

finish() {
    echo "# $(basename "$0"): $((CHECKS - FAILS)) of $CHECKS checks passed"
    [ "$FAILS" = 0 ]
}
