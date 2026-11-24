#!/bin/bash
# What processTheMoves does today with the planner's rows: where the names land, the counters and the log lines.
. "$(dirname "$0")/lib.sh"

for tool in rsync move; do
    begin "names with space, |, \$, quotes, a backslash and Unicode ($tool)" movefilesTool "$tool"
    names=('sh/o/a b.txt' 'sh/o/p|ipe.txt' 'sh/o/trail|' 'sh/o/$HOME.txt' "sh/o/q\"uote's.txt" 'sh/o/back\slash.txt' 'sh/o/ünï.txt')
    mk cache "${names[@]}"
    for n in "${names[@]}"; do row 'move from primary' f "$n"; done | list
    run_moves
    array_is sh sh/o "${names[@]}"
    cache_is sh sh/o
    counter MOVEDFILES 7
    counter REMAINING_CACHE_FILES 0
    counter MOVEDSIZE 14
    check "debug blocks written only with AGE_MOVER_DEBUG=2" "$([ "${AGE_MOVER_DEBUG:-0}" = 2 ] && echo yes || echo no)" \
        "$(grep -qF Debugging "$MOVER_DEBUG_LOG" && echo yes || echo no)"
    log_has 'Moving "/mnt/cache/./sh/o/trail|"  to  "/mnt/user0/"'
    log_has "Moving \"/mnt/cache/./sh/o/q\\\"uote's.txt\"  to  \"/mnt/user0/\""
    log_has 'Moving "/mnt/cache/./sh/o/back\\slash.txt"  to  "/mnt/user0/"'

    begin "hardlink group, every name listed ($tool)" movefilesTool "$tool"
    mk cache sh/h/a.txt
    ln /mnt/cache/sh/h/a.txt /mnt/cache/sh/h/b.txt
    { row 'move from primary' f sh/h/a.txt; row 'move from primary' f sh/h/b.txt; } | list
    run_moves
    array_is sh sh/h sh/h/a.txt sh/h/b.txt
    links 2 sh/h/b.txt
    counter MOVEDFILES 2
    counter MOVEDSIZE 2
    counter REMAINING_CACHE_SIZE 0
    log_count 1 'Moving "/mnt/cache/./sh/h/a.txt" "/mnt/cache/./sh/h/b.txt"  to  "/mnt/user0/" (preserving hardlinks)'

    begin "hardlink group across shares, both moved ($tool)" movefilesTool "$tool"
    mk cache sh1/h/a.txt sh2/k/z.txt
    ln /mnt/cache/sh1/h/a.txt /mnt/cache/sh2/k/b.txt
    { row 'move from primary' f sh1/h/a.txt; row 'move from primary' f sh2/k/b.txt; } | list
    run_moves
    array_is sh1 sh1/h sh1/h/a.txt sh2 sh2/k sh2/k/b.txt
    links 2 sh2/k/b.txt
    cache_is sh1 sh1/h sh2 sh2/k sh2/k/z.txt
    counter MOVEDFILES 2
    counter MOVEDSIZE 2
    log_count 1 'Moving "/mnt/cache/./sh1/h/a.txt" "/mnt/cache/./sh2/k/b.txt"  to  "/mnt/user0/" (preserving hardlinks)'

    begin "folder rows: empty, and one that gained a file after planning ($tool)" movefilesTool "$tool"
    mkdir -p /mnt/cache/sh/e/sub
    mk cache sh/g/new.txt
    { row 'move from primary' d sh/e/sub; row 'move from primary' d sh/g; } | list
    run_moves
    array_is sh sh/e sh/e/sub sh/g
    cache_is sh sh/g sh/g/new.txt
    counter MOVEDFOLDERS 2
    counter REMAINING_CACHE_FOLDERS 0
    log_has 'Deleted empty moved folder: /mnt/cache/sh/e'
    log_has 'Not deleting folder: contains 1 file(s), 0 subfolder(s): /mnt/cache/sh/g'

    begin "test mode ($tool)" movefilesTool "$tool" testmode yes synchronizeCache yes
    mk cache sh/t/f.txt sh/t/s.txt
    mkdir -p /mnt/cache/sh/t/e
    { row 'move from primary' f sh/t/f.txt; row 'move from primary' d sh/t/e; row 'sync from primary' f sh/t/s.txt; } | list
    run_moves
    array_is
    cache_is sh sh/t sh/t/e sh/t/f.txt sh/t/s.txt
    counter MOVEDFILES 0
    log_has "$([ "$tool" = move ] && echo 'TEST MODE: Would move using Unraid move utility' || echo 'TEST MODE: Would Move using rsync utility')"
    log_has 'TEST MODE: Would delete moved empty folder: /mnt/cache/sh/t/e'
    log_lacks 'Set last sync date'

    begin "move from secondary ($tool)" movefilesTool "$tool"
    mk disk1 sh/p/f.txt
    row 'move from secondary' f sh/p/f.txt | list
    run_moves
    cache_is sh sh/p sh/p/f.txt
    holds disk1 sh sh/p
    log_has 'Moving "/mnt/disk1/./sh/p/f.txt"  to  "/mnt/cache/"'
    log_has '0 files remaining from array to caches'

    begin "unattended file staged to the primary, then synced ($tool)" movefilesTool "$tool" synchronizeCache yes
    mk other sh/x/f.txt
    { row 'move unattended to primary' f sh/x/f.txt; row 'sync unattended to secondary' f sh/x/f.txt; } | list
    run_moves
    cache_is sh sh/x sh/x/f.txt
    array_is sh sh/x sh/x/f.txt
    counter MOVEDFILES 1
    counter REMAINING_UNATTENDED_FILES 0
    counter REMAINING_UNATTENDED_SIZE 0
    log_has 'Synchronizing  "/mnt/cache/./sh/x/f.txt"  to  "/mnt/user0/"'
    log_has 'Set last sync date in config file/s: 1767323045 = 2026-01-02T030405'
done

# bash read drops a | that ends the row, which would skip the check on a name like a|
for n in a.txt 'a|'; do
    begin "hardlink group with a name not listed, $n"
    mk cache "sh/h/$n" sh/k/z.txt
    ln "/mnt/cache/sh/h/$n" /mnt/cache/sh/k/b.txt
    row 'move from primary' f "sh/h/$n" | list
    run_moves
    array_is
    cache_is sh sh/h "sh/h/$n" sh/k sh/k/b.txt sh/k/z.txt
    counter NOTMOVEDFILES 1
    counter NOTMOVEDSIZE 2
    counter REMAINING_CACHE_SIZE 2
    log_has "Expected 2 files, got 1. Not moving \"/mnt/cache/./sh/h/$n\"  to prevent breaking hardlinks"
done

begin "hardlink group across shares, planned differently"
mk cache sh1/h/a.txt
mkdir -p /mnt/cache/sh2/k
ln /mnt/cache/sh1/h/a.txt /mnt/cache/sh2/k/b.txt
{ row 'move from primary' f sh1/h/a.txt; row 'keep on primary' f sh2/k/b.txt; } | list
run_moves
array_is
counter NOTMOVEDFILES 1
log_has 'Expected 2 files, got 1. Not moving "/mnt/cache/./sh1/h/a.txt"'

# each disk numbers its own inodes: the group lookup takes only the names on the row's disk
begin "hardlink groups on two disks sharing inode and mtime"
mk disk1 sh/p/a.txt
mk disk2 sh/p/b.txt
ln /mnt/disk1/sh/p/a.txt /mnt/disk1/sh/p/a2.txt
ln /mnt/disk2/sh/p/b.txt /mnt/disk2/sh/p/b2.txt
for n in a a2 b b2; do row 'move from secondary' f "sh/p/$n.txt" 2 777 1700000000; done | list
run_moves
cache_is sh sh/p sh/p/a.txt sh/p/a2.txt sh/p/b.txt sh/p/b2.txt
holds disk1 sh sh/p
holds disk2 sh sh/p
counter MOVEDFILES 4
counter MOVEDSIZE 4

# two ZFS datasets of one pool can give two single-link files the same inode number and mtime: each row moves its own file
begin "single-link files sharing inode and mtime across shares"
mk cache sh1/d/a.txt sh2/d/b.txt
{ row 'move from primary' f sh1/d/a.txt 1 777 1700000000; row 'move from primary' f sh2/d/b.txt 1 777 1700000000; } | list
run_moves
array_is sh1 sh1/d sh1/d/a.txt sh2 sh2/d sh2/d/b.txt
cache_is sh1 sh1/d sh2 sh2/d
counter MOVEDFILES 2
counter MOVEDSIZE 4
counter NOTMOVEDFILES 0
counter REMAINING_CACHE_FILES 0
counter REMAINING_CACHE_SIZE 0
log_has 'Moving "/mnt/cache/./sh1/d/a.txt"  to  "/mnt/user0/"'
log_has 'Moving "/mnt/cache/./sh2/d/b.txt"  to  "/mnt/user0/"'
log_lacks 'Expected 1 files'

# the same for two empty folders
begin "folder rows sharing inode and mtime across shares"
mkdir -p /mnt/cache/sh1/e /mnt/cache/sh2/e
{ row 'move from primary' d sh1/e 2 778 1700000000; row 'move from primary' d sh2/e 2 778 1700000000; } | list
run_moves
array_is sh1 sh1/e sh2 sh2/e
cache_is sh1 sh2
counter MOVEDFOLDERS 2
counter VANISHEDFOLDERS 0
counter REMAINING_CACHE_FOLDERS 0
log_has 'Moving "/mnt/cache/./sh1/e"  to  "/mnt/user0/"'
log_has 'Moving "/mnt/cache/./sh2/e"  to  "/mnt/user0/"'
log_lacks 'Gone from the source'

begin "a pass with nothing to move"
mk cache sh/k/k.txt
row 'keep on primary' f sh/k/k.txt | list
run_moves
array_is
cache_is sh sh/k sh/k/k.txt
log_lacks 'Moving'

begin "sync from primary keeps the file and sets the sync date" synchronizeCache yes
mk cache sh/y/f.txt
row 'sync from primary' f sh/y/f.txt | list
run_moves
cache_is sh sh/y sh/y/f.txt
array_is sh sh/y sh/y/f.txt
counter MOVEDFILES 1
counter MOVEDSIZE 2
check "lastCacheSync saved" 'lastCacheSync="1767323045"' "$(grep '^lastCacheSync=' "$T/cfg")"

# the in-use check covers every name of a hardlink group: here only the second name is open. A helper that does not
# compile leaves the check to fuser
shipped=$FILES_IN_USE_HELPER
for helper in shipped 'not compiling'; do
    begin "a hardlink group with one name held open, beside a free file, $helper helper"
    [ "$helper" = shipped ] || FILES_IN_USE_HELPER=$T/no_such_helper
    mk cache sh/u/a.txt sh/u/free.txt
    ln /mnt/cache/sh/u/a.txt /mnt/cache/sh/u/b.txt
    for n in a b free; do row 'move from primary' f "sh/u/$n.txt"; done | list
    sleep 60 9</mnt/cache/sh/u/b.txt &
    holder=$!
    for _ in {1..100}; do [ "$(readlink "/proc/$holder/fd/9" 2>/dev/null)" = /mnt/cache/sh/u/b.txt ] && break; sleep 0.05; done
    check "the holder has b.txt open" /mnt/cache/sh/u/b.txt "$(readlink "/proc/$holder/fd/9" 2>/dev/null)"
    run_moves
    kill "$holder"
    wait "$holder" 2>/dev/null
    FILES_IN_USE_HELPER=$shipped
    cache_is sh sh/u sh/u/a.txt sh/u/b.txt
    array_is sh sh/u sh/u/free.txt
    counter INUSEFILES 2
    counter MOVEDFILES 1
    log_has 'In use, left for a later run: "/mnt/cache/./sh/u/a.txt" "/mnt/cache/./sh/u/b.txt"'
    log_has '2 files were in use and stay on the source until a later run'
    if [ "$helper" = shipped ]; then
        log_lacks 'helper could not start'
    elif command -v perl >/dev/null; then
        log_has 'The file lease helper could not start'
    else
        log_has 'Perl not found'
    fi
    log_lacks 'could not be checked for use'
done

finish
