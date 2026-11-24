#!/bin/bash
# The folder cleanup after each row today: Clean Folders no / yes / topFolder, Move empty folders, Clean ZFS datasets.
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

# today the top folder is checked again on every later row once one file row emptied its folder
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
    log_count "$([ "$order" = file-first ] && echo 4 || echo 1)" 'top-level folder'
    log_has 'Not deleting top-level folder: contains 2 file(s), 2 subfolder(s): /mnt/cache/sh'
done

for left in no yes; do
    begin "Clean ZFS datasets, $([ $left = yes ] && echo 'a file left in the share' || echo 'a share that empties')" \
        cleanFolders topFolder cleanDatasets yes
    mk cache sh/only/f.txt
    [ "$left" = yes ] && mk cache sh/keep/k.txt
    printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
    row 'move from primary' f sh/only/f.txt | list
    run_moves
    if [ "$left" = no ]; then
        check "zfs calls" "$(printf 'zfs %s cache/sh\n' 'list -Hpo usedbychildren' 'list -r -H -o name' unmount destroy)" "$(cat "$T/zfs.calls")"
        log_has 'ZFS dataset [cache/sh] successfully destroyed.'
        log_has 'Skipping deletion of ZFS dataset mountpoint: /mnt/cache/sh'
    else
        check "no zfs calls" "" "$(cat "$T/zfs.calls" 2>/dev/null)"
    fi
done

id tester >/dev/null 2>&1 || useradd -M tester
U=/tmp/age_mover_tester
for keep in no yes; do
    begin "topFolder, a top folder its user cannot list, $([ $keep = yes ] && echo 'holding a file' || echo 'empty after the move')"
    mk cache sh/only/f.txt
    [ "$keep" = yes ] && mk cache sh/stay.txt
    rm -rf "$U" && mkdir -p "$U"
    row 'move from primary' f sh/only/f.txt | { echo "$HDR"; cat; } >"$U/actions"
    chown -R tester /mnt/cache /mnt/user0 "$U"
    chmod 0333 /mnt/cache/sh
    runuser -u tester -- env AGE_MOVER_TEST=1 AGE_MOVER_DEBUG="${AGE_MOVER_DEBUG:-0}" T="$U" bash "$0" --as-tester "$CASE" "$keep"
    check "the checks run as the mover's user pass" 0 "$?"
    [ ! -d /mnt/cache/sh ] || chmod 0755 /mnt/cache/sh
    if [ "$keep" = yes ]; then cache_is sh sh/stay.txt; else cache_is; fi
done

finish
