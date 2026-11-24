#!/bin/bash
# Clean ZFS datasets: after the pass, a share's dataset is destroyed only when nothing in it would be lost.
. "$(dirname "$0")/lib.sh"

# the half of the unreadable-subfolder case that runs as a plain user, since root lists any folder
if [ "${1:-}" = --as-tester ]; then
    CASE=$2
    fresh cleanFolders topFolder cleanDatasets yes
    # the dataset check's find, then the top-folder check's two, cannot list sh/locked
    run_moves "$(printf '%s\n' "find: './locked': Permission denied" "find: '/mnt/cache/sh/locked': Permission denied" \
        "find: '/mnt/cache/sh/locked': Permission denied")"
    log_lacks 'ZFS dataset [cache/sh]'
    [ "${AGE_MOVER_DEBUG:-0}" != 2 ] || dlog_has 'Keeping ZFS dataset [cache/sh]: a destroy could lose "/mnt/cache/sh"'
    [ "$FAILS" = 0 ]
    exit
fi

LS='list -r -H -t filesystem,volume,snapshot -o name'
# a destroy's calls: list, unmount, the check at a private read-only mount, destroy
DESTROYED=$(printf '%s\n' "zfs $LS cache/sh" 'zfs unmount cache/sh' 'mount -t zfs -o ro,zfsutil cache/sh PRIVATE' 'umount PRIVATE' \
    'zfs destroy cache/sh')
NOTICE='warning|Clean ZFS datasets did not finish for [cache/sh]: see the mover log.'
no_private() { check "no private mount folder left" "" "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'ca.mover.tuning.*')"; }
notices() { check "notices" "$1" "$(cat "$NOTIFY_LOG" 2>/dev/null)"; }
# the destroy goes ahead only when it loses nothing: each entry left is a folder the array also has
for left in nothing 'a middle folder the array has' '.zfs, as snapdir=visible shows it,' 'a file' 'a file beside it' 'a symlink' \
    'an empty folder the array lacks' 'a nested .zfs folder the array lacks'; do
    begin "Clean ZFS datasets, $left left in the share" cleanFolders topFolder cleanDatasets yes
    f=sh/only/f.txt
    [ "$left" = 'a middle folder the array has' ] && f=sh/a/b/f.txt
    mk cache "$f"
    case $left in
    'a file') mk cache sh/keep/k.txt; kept=(sh/keep sh/keep/k.txt) ;;
    'a file beside it') mk cache sh/only/g.txt; kept=(sh/only sh/only/g.txt) ;;
    'a symlink') ln -s /nowhere /mnt/cache/sh/link; kept=(sh/link) ;;
    'an empty folder'*) mkdir /mnt/cache/sh/e; kept=(sh/e) ;;
    .zfs*) mkdir -p /mnt/cache/sh/.zfs/snapshot /mnt/cache/sh/.zfs/shares ;;
    'a nested .zfs'*) mkdir /mnt/cache/sh/only/.zfs; kept=(sh/only sh/only/.zfs) ;;
    esac
    printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
    row 'move from primary' f "$f" | list
    run_moves
    if [ "$f" = sh/a/b/f.txt ]; then array_is sh sh/a sh/a/b "$f"; else array_is sh sh/only "$f"; fi
    case $left in
    nothing | 'a middle'* | .zfs*)
        check "zfs calls" "$DESTROYED" "$(cat "$T/zfs.calls")"
        log_has 'ZFS dataset [cache/sh] successfully destroyed.'
        cache_is
        no_private
        log_lacks 'top-level'
        ;;
    *)
        if [ "$left" = 'a file beside it' ]; then calls=; else calls="zfs $LS cache/sh"; fi
        check "zfs calls" "$calls" "$(cat "$T/zfs.calls" 2>/dev/null)"
        log_lacks 'ZFS dataset [cache/sh]'
        cache_is sh "${kept[@]}"
        if [ "${AGE_MOVER_DEBUG:-0}" != 2 ]; then
            :
        elif [ "$left" = 'a file beside it' ]; then
            # the row's folder keeps a file, so the row notes no dataset
            dlog_lacks 'Keeping ZFS dataset'
        else
            dlog_has "Keeping ZFS dataset [cache/sh]: a destroy could lose \"/mnt/cache/${kept[-1]}\""
        fi
        ;;
    esac
done

# zfs lists before the content check, so that check sees a file written while it lists
begin "Clean ZFS datasets, a file lands in the share while zfs lists its children" cleanFolders topFolder cleanDatasets yes
mk cache sh/only/f.txt
printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
echo 'echo x >/mnt/cache/sh/new.txt' >"$T/zfs.on_list"
row 'move from primary' f sh/only/f.txt | list
run_moves
check "zfs calls" "zfs $LS cache/sh" "$(cat "$T/zfs.calls")"
cache_is sh sh/new.txt
[ "${AGE_MOVER_DEBUG:-0}" != 2 ] || dlog_has 'Keeping ZFS dataset [cache/sh]: a destroy could lose "/mnt/cache/sh/new.txt"'

# a file written after the content check, as zfs unmounts, is in the dataset: the check at the private mount keeps it
begin "Clean ZFS datasets, a file lands in the share while zfs unmounts it" cleanFolders topFolder cleanDatasets yes
mk cache sh/only/f.txt
printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
echo 'echo x >/mnt/cache/sh/new.txt' >"$T/zfs.on_unmount"
row 'move from primary' f sh/only/f.txt | list
run_moves
check "zfs calls" "$(sed '$d' <<<"$DESTROYED"; echo 'zfs mount cache/sh')" "$(cat "$T/zfs.calls")"
log_has 'Keeping ZFS dataset [cache/sh]: the check after the unmount found something a destroy could lose.'
log_lacks 'successfully destroyed'
log_lacks 'Failed to'
cache_is sh sh/new.txt
no_private
notices ''
[ "${AGE_MOVER_DEBUG:-0}" != 2 ] || dlog_has 'Keeping ZFS dataset [cache/sh]: a destroy could lose "/mnt/cache/sh/new.txt"'

# the same, and a write through /mnt/user lands in the bare folder while the dataset is away: kept, not mounted over it
begin "Clean ZFS datasets, files land in the dataset and in its bare folder while it is unmounted" cleanFolders topFolder \
    cleanDatasets yes
mk cache sh/only/f.txt
printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
echo 'echo x >/mnt/cache/sh/new.txt' >"$T/zfs.on_unmount"
echo 'echo y >/mnt/cache/sh/bare.txt' >"$T/zfs.on_mount.zfs"
row 'move from primary' f sh/only/f.txt | list
run_moves
check "zfs calls" "$(sed '$d' <<<"$DESTROYED")" "$(cat "$T/zfs.calls")"
log_has 'Keeping ZFS dataset [cache/sh]: the check after the unmount found something a destroy could lose.'
log_has 'Not remounting ZFS dataset [cache/sh]: its folder /mnt/cache/sh holds files that a mount would hide'
cache_is sh sh/bare.txt
check "the unmounted dataset keeps its file" new.txt "$(ls "$T/zfs.store/cache/sh")"
no_private
notices "$NOTICE"

# one notice for the run at its worst level: an unmount that fails, then a check that fails, still reach errorsOnly
begin "Clean ZFS datasets, two datasets fail" cleanFolders topFolder cleanDatasets yes notify errorsOnly
mk cache a/only/f.txt sh/only/g.txt
printf '%s\n' /mnt/cache /mnt/cache/a /mnt/cache/sh >"$T/zfs"
# cache/a leaves the mount table as zfs starts to unmount it; cache/sh unmounts, then its read-only mount fails
printf "sed -i '\\|^/mnt/cache/a$|d' %q\n" "$T/zfs" >"$T/zfs.on_unmount"
echo mount.zfs >"$T/zfs.fail"
{ row 'move from primary' f a/only/f.txt; row 'move from primary' f sh/only/g.txt; } | list
run_moves
log_has 'Failed to unmount ZFS dataset [cache/a]'
log_has 'zfs: not currently mounted'
log_has "ZFS dataset [cache/sh] could not be checked once unmounted, will not delete: mount: filesystem 'cache/sh' cannot be mounted: zfs.fail"
notices 'warning|Clean ZFS datasets did not finish for [cache/a] [cache/sh]: see the mover log.'
no_private

# the kept name never passed the planner: a newline in it must not end the debug line before debug_mover mangles it
begin "Clean ZFS datasets, a file named with a newline left in the share" cleanFolders topFolder cleanDatasets yes
mk cache sh/only/f.txt
printf 'x\n' >$'/mnt/cache/sh/Tax\nSecret.pdf'
printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
row 'move from primary' f sh/only/f.txt | list
run_moves
check "zfs calls" "zfs $LS cache/sh" "$(cat "$T/zfs.calls")"
if [ "${AGE_MOVER_DEBUG:-0}" = 2 ]; then
    sed -n "/^cat >\"\$ANONAWK\" <<'ANONEOF'\$/,/^ANONEOF\$/p" "$PLUGIN/debug_mover" | sed '1d;$d' >"$T/anon.awk"
    anon=$(gawk -v POOLS='user user0 cache' -v SHARES=sh -v LIST=0 -f "$T/anon.awk" "$MOVER_DEBUG_LOG")
    check "debug_mover mangles the whole name" 'could lose "/mnt/cache/sh/-----------.pdf"' "$(grep -o 'could lose .*' <<<"$anon")"
fi

# a folder row that empties the share notes its dataset as a file row does, with Clean empty folders on only
for clean in topFolder no; do
    begin "Clean ZFS datasets, Clean empty folders $clean, a folder row empties the share" cleanFolders $clean cleanDatasets yes
    mkdir -p /mnt/cache/sh/new
    printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
    row 'move from primary' d sh/new | list
    run_moves
    array_is sh sh/new
    if [ $clean = no ]; then calls=; else calls=$DESTROYED; fi
    check "zfs calls" "$calls" "$(cat "$T/zfs.calls" 2>/dev/null)"
    if [ $clean = no ]; then cache_is sh; else cache_is; fi
done

for has in 'a snapshot' 'another name'; do
    begin "Clean ZFS datasets, the share's dataset has $has" cleanFolders topFolder cleanDatasets yes
    mk cache sh/only/f.txt
    row 'move from primary' f sh/only/f.txt | list
    if [ "$has" = 'a snapshot' ]; then
        printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
        echo cache/sh@daily >"$T/zfs.children"
        # as snapdir=visible shows it: the content check skips .zfs, so the snapshot is what keeps the dataset
        mk cache sh/.zfs/snapshot/daily/f.txt
        run_moves
        check "zfs calls" "zfs $LS cache/sh" "$(cat "$T/zfs.calls")"
        log_has 'ZFS dataset [cache/sh] has child datasets or snapshots, will not delete...'
        cache_is sh sh/.zfs sh/.zfs/snapshot sh/.zfs/snapshot/daily sh/.zfs/snapshot/daily/f.txt
    else
        # only dataset pool/share at /mnt/pool/share is destroyed; another dataset mounted there is kept
        printf '/mnt/cache\n/mnt/cache/sh\tcache/data/sh\n' >"$T/zfs"
        run_moves
        check "no zfs calls" "" "$(cat "$T/zfs.calls" 2>/dev/null)"
        log_lacks 'ZFS dataset ['
        cache_is sh
        [ "${AGE_MOVER_DEBUG:-0}" != 2 ] || dlog_has 'Keeping the ZFS dataset mounted at "/mnt/cache/sh": it is not cache/sh'
    fi
done

# once per share, after the pass, and only for rows that emptied a folder on the primary
begin "Clean ZFS datasets, a pass empties two folders of a share that keeps a file" cleanFolders topFolder cleanDatasets yes
mk cache sh/a/f.txt sh/b/g.txt sh/keep/k.txt
printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
{ row 'move from primary' f sh/a/f.txt; row 'move from primary' f sh/b/g.txt; } | list
run_moves
check "zfs calls" "zfs $LS cache/sh" "$(cat "$T/zfs.calls")"
cache_is sh sh/keep sh/keep/k.txt

begin "Clean ZFS datasets, a .placeholder keeps the folder after a row that emptied another share's" cleanFolders topFolder cleanDatasets yes
mk cache a/x/f.txt sh/y/g.txt sh/y/.placeholder
printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
{ row 'move from primary' f a/x/f.txt; row 'move from primary' f sh/y/g.txt; } | list
run_moves
check "no zfs calls" "" "$(cat "$T/zfs.calls" 2>/dev/null)"
cache_is sh sh/y sh/y/.placeholder

begin "Clean ZFS datasets, a move from the secondary empties its folder on the array" cleanFolders topFolder cleanDatasets yes
mk disk1 sh/only/f.txt
printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
row 'move from secondary' f sh/only/f.txt | list
run_moves
check "no zfs calls" "" "$(cat "$T/zfs.calls" 2>/dev/null)"
cache_is sh sh/only sh/only/f.txt

# test mode never destroys a dataset, even when the row's folder counts empty: here its file is gone before the run
begin "Clean ZFS datasets in test mode, the row's file gone before the run" cleanFolders topFolder cleanDatasets yes testmode yes
mk cache sh/f.txt
printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
row 'move from primary' f sh/f.txt | list
rm /mnt/cache/sh/f.txt
run_moves
check "no zfs calls" "" "$(cat "$T/zfs.calls" 2>/dev/null)"
cache_is sh
log_has 'TEST MODE: Would delete empty top-level folder: /mnt/cache/sh'

for pool in 'not ZFS' 'ZFS, the share a plain folder on it'; do
    begin "Clean ZFS datasets, a share that empties on a pool that is $pool" cleanFolders topFolder cleanDatasets yes
    mk cache sh/only/f.txt
    [ "$pool" = 'not ZFS' ] || echo /mnt/cache >"$T/zfs"
    row 'move from primary' f sh/only/f.txt | list
    run_moves
    check "no zfs calls" "" "$(cat "$T/zfs.calls" 2>/dev/null)"
    cache_is
    log_has 'Deleted empty top-level folder: /mnt/cache/sh'
    [ "${AGE_MOVER_DEBUG:-0}" != 2 ] || dlog_lacks 'Keeping'
done

# errorsOnly sends only a failure: a failed unmount or destroy notifies, a failed check or remount only warns
for fail in list unmount 'unmount, busy,' destroy 'destroy and mount' 'destroy, busy,' 'the read-only mount' \
    'the read-only unmount' mktemp; do
    what="zfs $fail"
    [[ $fail != the* && $fail != mktemp ]] || what=$fail
    begin "Clean ZFS datasets, $what fails" cleanFolders topFolder cleanDatasets yes notify errorsOnly
    mk cache sh/only/f.txt
    printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
    case $fail in
    'destroy and mount') printf '%s\n' destroy mount ;;
    'unmount, busy,') echo unmount; echo 'pool or dataset is busy' >"$T/zfs.reason" ;;
    'destroy, busy,') echo destroy; echo 'dataset is busy' >"$T/zfs.reason" ;;
    'the read-only mount') echo mount.zfs ;;
    'the read-only unmount') echo umount ;;
    mktemp) ;;
    *) echo "$fail" ;;
    esac >"$T/zfs.fail"
    row 'move from primary' f sh/only/f.txt | list
    # age_mover's stderr is discarded in use, so zfs's reason goes to the log, without the child zfs names after it
    if [ "$fail" = mktemp ]; then TMPDIR=/nowhere run_moves; else run_moves; fi
    private=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'ca.mover.tuning.*')
    unchecked="ZFS dataset [cache/sh] could not be checked once unmounted, will not delete:"
    case $fail in
    list) log_has "ZFS dataset [cache/sh] could not be listed, will not delete: zfs.fail" ;;
    'the read-only mount') log_has "$unchecked mount: filesystem 'cache/sh' cannot be mounted: zfs.fail" ;;
    'the read-only unmount') log_has "$unchecked umount: $private: zfs.fail" ;;
    mktemp) log_has "$unchecked mktemp: No such file or directory" ;;
    # the failure notice goes out with the "Failed to" line
    *busy*)
        log_has "ZFS dataset [cache/sh] is busy, will not delete: a process or another mount, such as a container's, may hold it."
        log_lacks "Failed to ${fail%%,*}"
        ;;
    *) log_has "Failed to ${fail%% *} ZFS dataset [cache/sh]"; log_has 'zfs: zfs.fail' ;;
    esac
    log_lacks 'cache/sh/child'
    array_is sh sh/only sh/only/f.txt
    # the row still logs and counts what it moved
    log_has '0 files remaining from caches to array'
    counter REMAINING_CACHE_FILES 0
    case $fail in unmount | destroy | 'destroy and mount') notices "$NOTICE" ;; *) notices '' ;; esac
    if [ "$fail" = 'destroy and mount' ]; then
        log_has 'Failed to remount dataset [cache/sh]'
        log_count 2 'zfs: zfs.fail'
        no_private
        continue
    fi
    # an unmount that fails leaves the dataset at the private folder, which zfs mount then refuses
    if [ "$fail" = 'the read-only unmount' ]; then
        check "the dataset stays at the private folder" "$private"$'\t'cache/sh "$(cat "$T/zfs.private")"
        log_has 'Failed to remount dataset [cache/sh]'
        log_has 'zfs: filesystem already mounted'
        continue
    fi
    no_private
    # the dataset is mounted at the end, so its top folder stays
    cache_is sh
    log_lacks 'Failed to remount'
    log_has 'Skipping deletion of ZFS dataset mountpoint: /mnt/cache/sh'
done

# a write through /mnt/user while the dataset is unmounted lands in its bare folder, which a remount would hide
begin "Clean ZFS datasets, a file lands in the unmounted share's folder before a failed destroy" cleanFolders topFolder \
    cleanDatasets yes
mk cache sh/only/f.txt
printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
echo destroy >"$T/zfs.fail"
echo 'echo x >/mnt/cache/sh/new.txt' >"$T/zfs.on_destroy"
row 'move from primary' f sh/only/f.txt | list
run_moves
check "zfs calls" "$DESTROYED" "$(cat "$T/zfs.calls")"
log_has 'Failed to remount dataset [cache/sh]'
log_has 'Not remounting ZFS dataset [cache/sh]: its folder /mnt/cache/sh holds files that a mount would hide'
cache_is sh sh/new.txt
no_private
notices "$NOTICE"

id tester >/dev/null 2>&1 || useradd -M tester
U=/tmp/age_mover_tester
# a find that fails keeps the dataset: the file the plain user cannot see would go with it
begin "Clean ZFS datasets, a subfolder a plain-user mover cannot list" cleanFolders topFolder cleanDatasets yes
mk cache sh/only/f.txt sh/locked/k.txt
rm -rf "$U" && mkdir -p "$U"
printf '%s\n' /mnt/cache /mnt/cache/sh >"$U/zfs"
row 'move from primary' f sh/only/f.txt | { echo "$HDR"; cat; } >"$U/actions"
chown -R tester /mnt/cache /mnt/user0 "$U"
chmod 0333 /mnt/cache/sh/locked
runuser -u tester -- env AGE_MOVER_TEST=1 AGE_MOVER_DEBUG="${AGE_MOVER_DEBUG:-0}" T="$U" bash "$0" --as-tester "$CASE"
check "the checks run as the plain user pass" 0 "$?"
check "zfs calls" "zfs $LS cache/sh" "$(cat "$U/zfs.calls" 2>/dev/null)"
[ ! -d /mnt/cache/sh/locked ] || chmod 0755 /mnt/cache/sh/locked
cache_is sh sh/locked sh/locked/k.txt

finish
