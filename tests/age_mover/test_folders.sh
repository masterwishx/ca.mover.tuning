#!/bin/bash
# The folder cleanup after each row and the top-folder check after the pass: Clean Folders no / yes / topFolder, Move
# empty folders, Clean ZFS datasets.
. "$(dirname "$0")/lib.sh"

# the half of an unreadable-folder case that runs as a plain user, since root lists any folder
if [ "${1:-}" = --as-tester ]; then
    CASE=$2
    if [ "$3" = dataset ]; then
        fresh cleanFolders topFolder cleanDatasets yes
        # the dataset check's find, then the top-folder check's two, cannot list sh/locked
        run_moves "$(printf '%s\n' "find: './locked': Permission denied" "find: '/mnt/cache/sh/locked': Permission denied" \
            "find: '/mnt/cache/sh/locked': Permission denied")"
        log_lacks 'ZFS dataset [cache/sh]'
        [ "${AGE_MOVER_DEBUG:-0}" != 2 ] || dlog_has 'Keeping ZFS dataset [cache/sh]: a destroy could lose "/mnt/cache/sh"'
        [ "$FAILS" = 0 ]
        exit
    fi
    fresh cleanFolders topFolder
    # today find's error on the unreadable top folder reaches stderr, once for its files and once for its subfolders
    run_moves "$(printf "find: '/mnt/cache/sh': Permission denied\n%.0s" 1 2)"
    log_has 'Deleted empty folder: /mnt/cache/sh/only'
    if [ "$3" = yes ]; then log_lacks 'top-level'; else log_has 'Deleted empty top-level folder: /mnt/cache/sh'; fi
    [ "$FAILS" = 0 ]
    exit
fi

for cf in no yes topFolder; do
    begin "Clean Folders $cf, a share that empties" cleanFolders "$cf"
    mk cache sh/only/f.txt sh/only/g.txt
    { row 'move from primary' f sh/only/f.txt; row 'move from primary' f sh/only/g.txt; } | list
    run_moves
    array_is sh sh/only sh/only/f.txt sh/only/g.txt
    case $cf in
    no) cache_is sh sh/only; log_lacks 'Deleted' ;;
    yes) cache_is sh; log_has 'Deleted empty folder: /mnt/cache/sh/only'; log_lacks 'top-level' ;;
    topFolder) cache_is; log_has 'Deleted empty top-level folder: /mnt/cache/sh' ;;
    esac
    [ "$cf" = no ] || log_has 'Not deleting folder containing 1 files: /mnt/cache/sh/only'
done

begin "topFolder, a share that keeps a file elsewhere" cleanFolders topFolder
mk cache sh/a/f.txt sh/keep/k.txt
row 'move from primary' f sh/a/f.txt | list
run_moves
cache_is sh sh/keep sh/keep/k.txt
log_has 'Not deleting top-level folder: contains 1 file(s), 1 subfolder(s): /mnt/cache/sh'

begin "topFolder, the file's folder keeps another file" cleanFolders topFolder
mk cache sh/a/f.txt sh/a/g.txt
row 'move from primary' f sh/a/f.txt | list
run_moves
cache_is sh sh/a sh/a/g.txt
log_has 'Not deleting folder containing 1 files: /mnt/cache/sh/a'
log_lacks 'top-level'

# the count takes files only, so the folder looks empty: rmdir alone keeps the subfolder's file
begin "topFolder, the file's folder keeps a subfolder with a file" cleanFolders topFolder
mk cache sh/a/f.txt sh/a/sub/g.txt
row 'move from primary' f sh/a/f.txt | list
run_moves
cache_is sh sh/a sh/a/sub sh/a/sub/g.txt
log_has 'Not deleting top-level folder: contains 1 file(s), 2 subfolder(s): /mnt/cache/sh'

begin "topFolder, .placeholder in the file's folder" cleanFolders topFolder
mk cache sh/a/f.txt sh/a/.placeholder
row 'move from primary' f sh/a/f.txt | list
run_moves
cache_is sh sh/a sh/a/.placeholder
log_has 'Not deleting folder containing .placeholder file: /mnt/cache/sh/a'
log_lacks 'top-level'

begin "topFolder, .placeholder in the top folder" cleanFolders topFolder
mk cache sh/only/f.txt sh/.placeholder
row 'move from primary' f sh/only/f.txt | list
run_moves
cache_is sh sh/.placeholder
log_has 'Not deleting top-level folder: contains .placeholder: /mnt/cache/sh'

begin "topFolder, a hidden file in the top folder" cleanFolders topFolder
mk cache sh/only/f.txt sh/.hidden
row 'move from primary' f sh/only/f.txt | list
run_moves
cache_is sh sh/.hidden
log_has 'Not deleting top-level folder: contains 1 file(s), 0 subfolder(s): /mnt/cache/sh'

# find counts no symlink, so the folder looks empty and only rmdir keeps it
begin "topFolder, only a symlink left in the top folder" cleanFolders topFolder
mk cache sh/only/f.txt
ln -s /nowhere /mnt/cache/sh/dangling
row 'move from primary' f sh/only/f.txt | list
run_moves
cache_is sh sh/dangling
log_lacks 'top-level'
[ "${AGE_MOVER_DEBUG:-0}" != 2 ] || dlog_has 'Failed to delete top-level folder (may not be empty): /mnt/cache/sh'

for tm in no yes; do
    begin "topFolder, the top folder is a ZFS dataset mountpoint, test mode $tm" cleanFolders topFolder testmode "$tm"
    mk cache sh/only/f.txt
    echo /mnt/cache/sh >"$T/zfs"
    row 'move from primary' f sh/only/f.txt | list
    run_moves
    if [ "$tm" = no ]; then
        cache_is sh
        log_has 'Skipping deletion of ZFS dataset mountpoint: /mnt/cache/sh'
    else
        cache_is sh sh/only sh/only/f.txt
        log_has 'Not deleting folder containing 1 files: /mnt/cache/sh/only'
        log_lacks 'top-level'
    fi
done

begin "topFolder in test mode, a share holding one empty folder" cleanFolders topFolder testmode yes
mkdir -p /mnt/cache/sh/e
row 'move from primary' d sh/e | list
run_moves
cache_is sh sh/e
log_has 'TEST MODE: Would delete moved empty folder: /mnt/cache/sh/e'
log_has 'Not deleting top-level folder: contains 0 file(s), 1 subfolder(s): /mnt/cache/sh'

# with Move empty folders off the planner lists no folder rows, so an empty folder stays and keeps the top folder
begin "topFolder, Move empty folders no, an empty folder not listed" cleanFolders topFolder moveEmptyFolders no
mk cache sh/a/f.txt
mkdir -p /mnt/cache/sh/e
row 'move from primary' f sh/a/f.txt | list
run_moves
cache_is sh sh/e
log_has 'Not deleting top-level folder: contains 0 file(s), 1 subfolder(s): /mnt/cache/sh'

for tool in rsync move; do
    begin "topFolder, a folder row empties the share last ($tool)" cleanFolders topFolder movefilesTool "$tool"
    mk cache sh/a/f.txt
    mkdir -p /mnt/cache/sh/e
    { row 'move from primary' f sh/a/f.txt; row 'move from primary' d sh/e; } | list
    run_moves
    cache_is
    array_is sh sh/a sh/a/f.txt sh/e
    log_has 'Deleted empty top-level folder: /mnt/cache/sh'
done

# with move the cleanup finds the folder already gone, and its parent is the top folder
for tool in rsync move; do
    begin "topFolder, a share holding only an empty folder ($tool)" cleanFolders topFolder movefilesTool "$tool"
    mkdir -p /mnt/cache/sh/e
    row 'move from primary' d sh/e | list
    run_moves
    cache_is
    array_is sh sh/e
    log_has 'Deleted empty top-level folder: /mnt/cache/sh'
done

begin "topFolder, a folder row whose parent keeps a file" cleanFolders topFolder
mk cache sh/p/k.txt
mkdir -p /mnt/cache/sh/p/e
row 'move from primary' d sh/p/e | list
run_moves
cache_is sh sh/p sh/p/k.txt
log_has 'Not deleting folder: contains 1 file(s), 0 subfolder(s): /mnt/cache/sh/p'
log_lacks 'top-level'

# the reporter's shape: one top-folder check for the share, whichever row empties a folder first
for order in file-first folders-first; do
    begin "topFolder, one file row and three folder rows, $order" cleanFolders topFolder
    mk cache sh/a/f.txt sh/p/other.txt sh/keep/stay.txt
    mkdir -p /mnt/cache/sh/p/e1 /mnt/cache/sh/p/e2 /mnt/cache/sh/p/e3
    {
        [ "$order" = file-first ] && row 'move from primary' f sh/a/f.txt
        for d in e1 e2 e3; do row 'move from primary' d "sh/p/$d"; done
        [ "$order" = folders-first ] && row 'move from primary' f sh/a/f.txt
    } | list
    run_moves
    cache_is sh sh/keep sh/keep/stay.txt sh/p sh/p/other.txt
    log_count 1 'top-level folder'
    log_has 'Not deleting top-level folder: contains 2 file(s), 2 subfolder(s): /mnt/cache/sh'
done

begin "topFolder, two shares, their rows taking turns" cleanFolders topFolder
mk cache s1/a/f.txt s1/b/g.txt s1/keep/k.txt s2/a/f.txt s2/b/g.txt
for f in s1/a/f.txt s2/a/f.txt s1/b/g.txt s2/b/g.txt; do row 'move from primary' f "$f"; done | list
run_moves
cache_is s1 s1/keep s1/keep/k.txt
array_is s1 s1/a s1/a/f.txt s1/b s1/b/g.txt s2 s2/a s2/a/f.txt s2/b s2/b/g.txt
log_count 2 'top-level folder'
log_has 'Not deleting top-level folder: contains 1 file(s), 1 subfolder(s): /mnt/cache/s1'
log_has 'Deleted empty top-level folder: /mnt/cache/s2'

begin "topFolder, a soft stop after the first row" cleanFolders topFolder
mk cache sh/a/f.txt sh/b/g.txt
{ row 'move from primary' f sh/a/f.txt; row 'move from primary' f sh/b/g.txt; } | list
after_first_rsync "touch '$SOFTSTOPFILE'"
run_moves
array_is sh sh/a sh/a/f.txt
cache_is sh sh/b sh/b/g.txt
check "the top folder is checked after the soft stop" \
    "$(printf '%s\n' 'Soft Stopping requested' 'Not deleting top-level folder: contains 1 file(s), 1 subfolder(s): /mnt/cache/sh')" \
    "$(log | grep -oE 'Soft Stopping requested|Not deleting top-level folder.*')"

LS='list -r -H -t filesystem,volume,snapshot -o name'
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
        check "zfs calls" "$(printf 'zfs %s cache/sh\n' "$LS" unmount destroy)" "$(cat "$T/zfs.calls")"
        log_has 'ZFS dataset [cache/sh] successfully destroyed.'
        cache_is
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
    if [ $clean = no ]; then calls=; else calls=$(printf 'zfs %s cache/sh\n' "$LS" unmount destroy); fi
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

for fail in list unmount destroy 'destroy and mount' 'destroy, busy,'; do
    begin "Clean ZFS datasets, zfs $fail fails" cleanFolders topFolder cleanDatasets yes notify no
    mk cache sh/only/f.txt
    printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
    case $fail in
    'destroy and mount') printf '%s\n' destroy mount ;;
    *busy*) echo destroy; echo 'dataset is busy' >"$T/zfs.reason" ;;
    *) echo "$fail" ;;
    esac >"$T/zfs.fail"
    row 'move from primary' f sh/only/f.txt | list
    # age_mover's stderr is discarded in use, so zfs's reason goes to the log, without the child zfs names after it
    run_moves
    case $fail in
    list) log_has "ZFS dataset [cache/sh] could not be listed, will not delete: zfs.fail" ;;
    # the failure notice goes out with the "Failed to" line
    *busy*)
        log_has "ZFS dataset [cache/sh] is busy, will not delete: another mount, such as a container's, may hold it."
        log_lacks 'Failed to destroy'
        ;;
    *) log_has "Failed to ${fail%% *} ZFS dataset [cache/sh]"; log_has 'zfs: zfs.fail' ;;
    esac
    log_lacks 'cache/sh/child'
    array_is sh sh/only sh/only/f.txt
    # the row still logs and counts what it moved
    log_has '0 files remaining from caches to array'
    counter REMAINING_CACHE_FILES 0
    if [ "$fail" = 'destroy and mount' ]; then
        log_has 'Failed to remount dataset [cache/sh]'
        log_count 2 'zfs: zfs.fail'
        continue
    fi
    # the dataset is mounted at the end, so its top folder stays
    cache_is sh
    log_lacks 'Failed to remount'
    log_has 'Skipping deletion of ZFS dataset mountpoint: /mnt/cache/sh'
done

id tester >/dev/null 2>&1 || useradd -M tester
U=/tmp/age_mover_tester
for keep in no yes; do
    begin "topFolder, a top folder a plain-user mover cannot list, $([ $keep = yes ] && echo 'holding a file' || echo 'empty after the move')"
    mk cache sh/only/f.txt
    [ "$keep" = yes ] && mk cache sh/stay.txt
    rm -rf "$U" && mkdir -p "$U"
    row 'move from primary' f sh/only/f.txt | { echo "$HDR"; cat; } >"$U/actions"
    chown -R tester /mnt/cache /mnt/user0 "$U"
    chmod 0333 /mnt/cache/sh
    runuser -u tester -- env AGE_MOVER_TEST=1 AGE_MOVER_DEBUG="${AGE_MOVER_DEBUG:-0}" T="$U" bash "$0" --as-tester "$CASE" "$keep"
    check "the checks run as the plain user pass" 0 "$?"
    [ ! -d /mnt/cache/sh ] || chmod 0755 /mnt/cache/sh
    if [ "$keep" = yes ]; then cache_is sh sh/stay.txt; else cache_is; fi
done

# a find that fails keeps the dataset: the file the plain user cannot see would go with it
begin "Clean ZFS datasets, a subfolder a plain-user mover cannot list" cleanFolders topFolder cleanDatasets yes
mk cache sh/only/f.txt sh/locked/k.txt
rm -rf "$U" && mkdir -p "$U"
printf '%s\n' /mnt/cache /mnt/cache/sh >"$U/zfs"
row 'move from primary' f sh/only/f.txt | { echo "$HDR"; cat; } >"$U/actions"
chown -R tester /mnt/cache /mnt/user0 "$U"
chmod 0333 /mnt/cache/sh/locked
runuser -u tester -- env AGE_MOVER_TEST=1 AGE_MOVER_DEBUG="${AGE_MOVER_DEBUG:-0}" T="$U" bash "$0" --as-tester "$CASE" dataset
check "the checks run as the plain user pass" 0 "$?"
check "zfs calls" "zfs $LS cache/sh" "$(cat "$U/zfs.calls" 2>/dev/null)"
[ ! -d /mnt/cache/sh/locked ] || chmod 0755 /mnt/cache/sh/locked
cache_is sh sh/locked sh/locked/k.txt

finish
