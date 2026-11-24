#!/bin/bash
# The folder cleanup after each row and the top-folder check after the pass: Clean Folders no / yes / topFolder, Move
# empty folders, Clean ZFS datasets.
. "$(dirname "$0")/lib.sh"

# the half of an unreadable-folder case that runs as a plain user, since root lists any folder
if [ "${1:-}" = --as-tester ]; then
    CASE=$2
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

# today the destroy counts regular files only: an empty folder and a symlink go with the dataset
for left in nothing 'a file' 'an empty folder and a symlink'; do
    begin "Clean ZFS datasets, $left left in the share" cleanFolders topFolder cleanDatasets yes
    mk cache sh/only/f.txt
    case $left in
    'a file') mk cache sh/keep/k.txt ;;
    'an empty folder'*) mkdir /mnt/cache/sh/e && ln -s /nowhere /mnt/cache/sh/link ;;
    esac
    printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
    row 'move from primary' f sh/only/f.txt | list
    run_moves
    array_is sh sh/only sh/only/f.txt
    if [ "$left" = 'a file' ]; then
        check "no zfs calls" "" "$(cat "$T/zfs.calls" 2>/dev/null)"
        cache_is sh sh/keep sh/keep/k.txt
        log_has 'Not deleting top-level folder: contains 1 file(s), 1 subfolder(s): /mnt/cache/sh'
        continue
    fi
    check "zfs calls" "$(printf 'zfs %s cache/sh\n' 'list -Hpo usedbychildren' 'list -r -H -o name' unmount destroy)" "$(cat "$T/zfs.calls")"
    log_has 'ZFS dataset [cache/sh] successfully destroyed.'
    if [ "$left" = nothing ]; then cache_is; log_lacks 'top-level'; fi
done

begin "Clean ZFS datasets, a share that empties on a pool that is not ZFS" cleanFolders topFolder cleanDatasets yes
mk cache sh/only/f.txt
row 'move from primary' f sh/only/f.txt | list
run_moves
check "no zfs calls" "" "$(cat "$T/zfs.calls" 2>/dev/null)"
cache_is
log_has 'Deleted empty top-level folder: /mnt/cache/sh'

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

finish
