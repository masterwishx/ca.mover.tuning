#!/bin/bash
# Clean ZFS datasets: a stop lets the step in hand finish, mounts the dataset back where it can and ends the run after the
# notice.
. "$(dirname "$0")/lib.sh"

# a hook, run once, that stops the mover: Unraid's stop signals the run alone; the plugin's is age_mover stop, run outside
# the run, which signals every process of it. The hook waits for that stop to end
stop_hook() {
    cat <<EOF
rm -f "\$0"
p=\$PPID
while [ "\$(cut -d' ' -f4 /proc/\$p/stat)" != $$ ]; do p=\$(cut -d' ' -f4 /proc/\$p/stat); done
EOF
    # shellcheck disable=SC2016 # the hook expands its own $p
    if [ "$1" = run ]; then echo 'kill -TERM "$p"'; return; fi
    cat <<EOF
echo "\$p" >"$T/pid"
( setsid bash -c '. "$T/funcs.sh"; PIDFILE="$T/pid" MOVER_STATUS="$T/mover.ini" PAUSEFILE="$T/pause" MOVINGFILE="$T/moving"; stop' \\
    </dev/null >"$T/stop.out" 2>&1 & )
for _ in \$(seq 100); do grep -qs 'mover: stopped' "$T/stop.out" && break; sleep 0.1; done
EOF
}
# the plugin's stop ends with a sleep, then removes the pid and status files: it must end before the next case
stop_done() {
    local _
    for _ in $(seq 100); do grep -qs 'mover: stopped' "$T/stop.out" && break; sleep 0.1; done
    check "the plugin's stop ended" 'mover: stopped' "$(cat "$T/stop.out" 2>/dev/null)"
    rm -f "$T/stop.out"
}
# a hook, run once after command $2, that sends signal $1 to every process from its caller up to, not including, the run
kill_hook() {
    cat <<EOF
rm -f "\$0"
$2
p=\$PPID up=(\$PPID)
while [ "\$(cut -d' ' -f4 /proc/\$p/stat)" != $$ ]; do p=\$(cut -d' ' -f4 /proc/\$p/stat); up+=("\$p"); done
unset 'up[-1]'
kill -$1 "\${up[@]}"
EOF
}
# a $1 first on PATH, under $T/wrap, that runs $T/$1.hook when its arguments start with $2, then the real $1
wrap_hook() {
    mkdir -p "$T/wrap"
    cat >"$T/wrap/$1" <<EOF
#!/bin/bash
[[ \$* != "$2"* ]] || [ ! -f "$T/$1.hook" ] || bash "$T/$1.hook"
exec $(command -v "$1") "\$@"
EOF
    chmod 755 "$T/wrap/$1"
}
one_share() {
    mk cache sh/only/f.txt
    printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
    row 'move from primary' f sh/only/f.txt | list
}
mounted_again() { check "the dataset is mounted at its folder again" /mnt/cache/sh "$(grep -x /mnt/cache/sh "$T/zfs")"; }
REMOUNTED=$(sed '$d' <<<"$DESTROYED"; echo 'zfs mount cache/sh')

# Unraid's stop during the check after the unmount, and a write through /mnt/user meanwhile, which keeps it unmounted
begin "Clean ZFS datasets, Unraid's mover stop during the check after the unmount" cleanFolders topFolder cleanDatasets yes \
    notify errorsOnly
one_share
{ stop_hook run; echo 'echo y >/mnt/cache/sh/bare.txt'; } >"$T/zfs.on_mount.zfs"
run_moves 'processTheMoves did not return'
check "zfs calls" "$(sed '$d' <<<"$DESTROYED")" "$(cat "$T/zfs.calls")"
log_has 'Mover stopped while ZFS dataset [cache/sh] was unmounted: not deleting it, attempting to remount'
log_has 'Not remounting ZFS dataset [cache/sh]: its folder /mnt/cache/sh holds files that a mount would hide'
log_lacks 'successfully destroyed'
check "the dataset is kept, unmounted" yes "$([ -d "$T/zfs.store/cache/sh" ] && echo yes)"
cache_is sh sh/bare.txt
no_private
notices "$NOTICE"

# the plugin's stop as each step runs: the step finishes, a destroy that finished stays done, else the dataset goes back
for step in 'zfs list' 'zfs unmount' 'the read-only umount' 'zfs destroy' 'the remount'; do
    begin "Clean ZFS datasets, the plugin's mover stop during $step" cleanFolders topFolder cleanDatasets yes
    one_share
    case $step in
    'zfs list') stop_hook plugin >"$T/zfs.on_list" ;;
    'zfs unmount') stop_hook plugin >"$T/zfs.on_unmount" ;;
    'the read-only umount') stop_hook plugin >"$T/zfs.on_umount" ;;
    'zfs destroy') stop_hook plugin >"$T/zfs.on_destroy" ;;
    # a file that lands in the dataset as it unmounts keeps it, so it is mounted again
    *) echo 'echo x >/mnt/cache/sh/new.txt' >"$T/zfs.on_unmount"; stop_hook plugin >"$T/zfs.on_mount" ;;
    esac
    run_moves 'processTheMoves did not return'
    stop_done
    log_lacks 'Failed to'
    log_lacks 'could not be checked'
    no_private
    notices ''
    # the run ends after the dataset checks, before the top-folder check
    log_lacks 'top-level'
    if [ "$step" = 'zfs list' ]; then
        check "zfs calls" "zfs $LS cache/sh" "$(cat "$T/zfs.calls")"
        log_lacks 'could not be listed'
        check "the dataset stays mounted" /mnt/cache/sh "$(grep -x /mnt/cache/sh "$T/zfs")"
        continue
    fi
    if [ "$step" = 'zfs destroy' ]; then
        check "zfs calls" "$DESTROYED" "$(cat "$T/zfs.calls")"
        log_has 'ZFS dataset [cache/sh] successfully destroyed.'
        cache_is
        continue
    fi
    check "zfs calls" "$REMOUNTED" "$(cat "$T/zfs.calls")"
    check "no private mount left" "" "$(cat "$T/zfs.private" 2>/dev/null)"
    mounted_again
    if [ "$step" = 'the remount' ]; then
        log_has 'Keeping ZFS dataset [cache/sh]: the check after the unmount found something a destroy could lose.'
        cache_is sh sh/new.txt
    else
        log_has 'Mover stopped while ZFS dataset [cache/sh] was unmounted: not deleting it, attempting to remount'
        cache_is sh
    fi
done

# the plugin's stop as the remount's look into the bare folder runs: the look finishes and finds what a mount would hide
begin "Clean ZFS datasets, the plugin's mover stop as the remount looks into the bare folder" cleanFolders topFolder \
    cleanDatasets yes
one_share
wrap_hook find "/mnt/cache/sh -mindepth 1 -print -quit"
echo 'echo x >/mnt/cache/sh/new.txt' >"$T/zfs.on_unmount"
echo 'echo y >/mnt/cache/sh/bare.txt' >"$T/zfs.on_mount.zfs"
stop_hook plugin >"$T/find.hook"
PATH=$T/wrap:$PATH run_moves 'processTheMoves did not return'
stop_done
check "zfs calls" "$(sed '$d' <<<"$DESTROYED")" "$(cat "$T/zfs.calls")"
log_has 'Not remounting ZFS dataset [cache/sh]: its folder /mnt/cache/sh holds files that a mount would hide'
cache_is sh sh/bare.txt
no_private
notices "$NOTICE"

# the plugin's stop as mktemp makes the private folder: it is made, so the unmount goes ahead and the dataset goes back
begin "Clean ZFS datasets, the plugin's mover stop as the private folder is made" cleanFolders topFolder cleanDatasets yes
one_share
wrap_hook mktemp "-d -t ca.mover.tuning.XXXXXX"
stop_hook plugin >"$T/mktemp.hook"
PATH=$T/wrap:$PATH run_moves 'processTheMoves did not return'
stop_done
check "zfs calls" "$REMOUNTED" "$(cat "$T/zfs.calls")"
log_has 'Mover stopped while ZFS dataset [cache/sh] was unmounted: not deleting it, attempting to remount'
log_lacks 'could not be checked'
mounted_again
no_private
notices ''

# the plugin's stop signals the first check before the run: the check still finishes, so its find keeps the dataset
# mounted, where a cut-short check would read as nothing to lose and unmount it
begin "Clean ZFS datasets, a TERM to the first check before the run's" cleanFolders topFolder cleanDatasets yes
mk cache sh/only/f.txt sh/keep.txt
printf '%s\n' /mnt/cache /mnt/cache/sh >"$T/zfs"
row 'move from primary' f sh/only/f.txt | list
wrap_hook find ". -mindepth 1 -path ./.zfs -prune -o ! -type d -print -quit"
kill_hook TERM : >"$T/find.hook"
PATH=$T/wrap:$PATH run_moves
check "zfs calls" "zfs $LS cache/sh" "$(cat "$T/zfs.calls")"
log_lacks 'attempting to unmount'
cache_is sh sh/keep.txt
notices ''

# a stop during the next share's checks ends the run before its unmount and before the share after it, and still sends
# the notice for the earlier one
begin "Clean ZFS datasets, Unraid's mover stop during the next share's checks" cleanFolders topFolder cleanDatasets yes
mk cache a/only/f.txt sh/only/g.txt z/only/h.txt
printf '%s\n' /mnt/cache /mnt/cache/a /mnt/cache/sh /mnt/cache/z >"$T/zfs"
# cache/a is kept, as a file lands in it as it unmounts, and cannot be mounted again
echo 'echo x >/mnt/cache/a/new.txt' >"$T/zfs.on_unmount"
echo mount >"$T/zfs.fail"
{ echo "tail -n 1 \"$T/zfs.calls\" | grep -q ' cache/sh\$' || exit 0"; stop_hook run; } >"$T/zfs.on_list"
{ row 'move from primary' f a/only/f.txt; row 'move from primary' f sh/only/g.txt; row 'move from primary' f z/only/h.txt; } | list
run_moves 'processTheMoves did not return'
log_has 'Failed to remount dataset [cache/a]'
log_lacks 'ZFS dataset [cache/sh] holds only folders'
check "cache/sh is still mounted" /mnt/cache/sh "$(grep -x /mnt/cache/sh "$T/zfs")"
check "the share after it is not looked at" "" "$(grep -F cache/z "$T/zfs.calls")"
notices "$(notice_for '[cache/a]')"
no_private

# a check killed outright, not by a stop: the run unmounts the private folder if the dataset is there, then mounts it back,
# or says where it is and how to mount it back when that umount fails
for when in 'before the read-only mount' 'while it is mounted' 'while it is mounted, and the clean-up umount fails' \
    'while it is mounted, and the plugin stops the mover during the clean-up umount' \
    'while it is mounted, and the plugin stops the mover as the run looks for the private mount'; do
    begin "Clean ZFS datasets, the check after the unmount is killed $when" cleanFolders topFolder cleanDatasets yes
    one_share
    case $when in
    before*) kill_hook KILL : >"$T/zfs.on_mount.zfs" ;;
    *fails) kill_hook KILL "echo umount >\"$T/zfs.fail\"" >"$T/zfs.on_umount" ;;
    # the stop's hook takes the hook's place for the clean-up umount, which finishes and puts the dataset back
    *during*) stop_hook plugin >"$T/stop.hook"; kill_hook KILL "cp \"$T/stop.hook\" \"$T/zfs.on_umount\"" >"$T/zfs.on_umount" ;;
    # the look finishes, so the clean-up umount runs
    *looks*)
        wrap_hook findmnt "-no source --mountpoint $TMPDIR/ca.mover.tuning."
        stop_hook plugin >"$T/stop.hook"
        kill_hook KILL "cp \"$T/stop.hook\" \"$T/findmnt.hook\"" >"$T/zfs.on_umount"
        ;;
    *) kill_hook KILL : >"$T/zfs.on_umount" ;;
    esac
    if [[ $when == *mover* ]]; then
        PATH=$T/wrap:$PATH run_moves 'processTheMoves did not return'
        stop_done
    else
        run_moves
    fi
    private=$(find "$TMPDIR" -maxdepth 1 -name 'ca.mover.tuning.*')
    case $when in
    before*) calls=$(sed '$d' <<<"$REMOUNTED" | sed '$d'; echo 'zfs mount cache/sh') ;;
    *fails) calls=$(sed '$d' <<<"$DESTROYED"; echo 'umount PRIVATE') ;;
    *) calls=$(sed '$d' <<<"$DESTROYED"; printf '%s\n' 'umount PRIVATE' 'zfs mount cache/sh') ;;
    esac
    check "zfs calls" "$calls" "$(cat "$T/zfs.calls")"
    log_lacks 'successfully destroyed'
    if [[ $when == *mover* ]]; then
        log_has 'Mover stopped while ZFS dataset [cache/sh] was unmounted: not deleting it, attempting to remount'
        log_lacks 'still mounted read-only'
        notices ''
        mounted_again
        no_private
        continue
    fi
    notices "$NOTICE"
    if [[ $when == *fails ]]; then
        log_has "ZFS dataset [cache/sh] is still mounted read-only at $private, not at /mnt/cache/sh: umount: $private: zfs.fail"
        log_has "To mount it back: umount $private, then zfs mount cache/sh"
        check "the dataset stays at the private folder" "$private"$'\t'cache/sh "$(cat "$T/zfs.private")"
        continue
    fi
    log_has 'ZFS dataset [cache/sh] could not be checked once unmounted, will not delete: the check was cut short'
    mounted_again
    no_private
done

finish
