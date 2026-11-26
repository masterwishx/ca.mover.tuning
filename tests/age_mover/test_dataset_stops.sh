#!/bin/bash
# Clean ZFS datasets: a stop lets the step in hand finish, mounts the dataset back where it can and ends the run after the
# notice.
. "$(dirname "$0")/lib.sh"
# a case writes under /usr/local and /var/local: a mount at either refuses
if ! awk '$5 ~ "^/(usr|var)/local(/|$)" || $5 ~ "^/(usr|var)$" { exit 1 }' /proc/self/mountinfo; then
    echo "test_dataset_stops.sh writes Unraid's paths and one is a mount here: start it with tests/age_mover/run.sh" >&2
    exit 2
fi

# the plugin's stop waits for the run to end, then removes the pid and status files: it must end before the next case
stop_done() {
    local _
    for _ in $(seq 100); do grep -qs 'mover: stopped' "$T/stop.out" && break; sleep 0.1; done
    check "the plugin's stop waited for the run, then ended" \
        "mover: waiting for the run to end"$'\n''mover: stopped' "$(cat "$T/stop.out" 2>/dev/null)"
    check "the pid file stayed while the run finished" kept "$(cat "$T/pid.kept" 2>/dev/null)"
    check "the plugin's stop removed the pid file" "" "$(ls "$T/pid" 2>/dev/null)"
    rm -f "$T/stop.out" "$T/pid.kept"
}
# a hook, run once after command $2, that sends signal $1 to every process from its caller up to, not including, the run
# and its $3 (default 0) nearest
kill_hook() {
    cat <<EOF
rm -f "\$0"
$2
p=\$PPID up=(\$PPID)
while [ "\$(cut -d' ' -f4 /proc/\$p/stat)" != $$ ]; do p=\$(cut -d' ' -f4 /proc/\$p/stat); up+=("\$p"); done
kill -$1 "\${up[@]:0:\${#up[@]}-$((1 + ${3:-0}))}"
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

# a stop of the run alone during the check after the unmount, and a write through /mnt/user meanwhile, which keeps it
# unmounted. The run puts back the write method it forced, then removes its pid file
begin "Clean ZFS datasets, a stop of the run alone during the check after the unmount" cleanFolders topFolder \
    cleanDatasets yes notify errorsOnly enableTurbo yes
one_share
mkdir -p /usr/local/sbin /var/local/emhttp
echo 'md_write_method="0"' >/var/local/emhttp/var.ini
# shellcheck disable=SC2016 # the stand-in expands its own $* and $w
printf '#!/bin/bash\n[ ! -e %q ] || w=" (pid file there)"\necho "mdcmd $*$w" >>%q\n' "$T/pid" "$T/mdcmd.calls" >/usr/local/sbin/mdcmd
chmod 755 /usr/local/sbin/mdcmd
echo $$ >"$T/pid"
{ stop_hook run; echo 'echo y >/mnt/cache/sh/bare.txt'; } >"$T/zfs.on_mount.zfs"
run_moves 'processTheMoves did not return'
check "turbo write forced, then put back before the pid file goes" \
    "$(printf '%s\n' 'mdcmd set md_write_method 1 (pid file there)' 'mdcmd set md_write_method 0 (pid file there)')" \
    "$(cat "$T/mdcmd.calls")"
check "the run removed its pid file" "" "$(ls "$T/pid" 2>/dev/null)"
rm -rf /usr/local/sbin/mdcmd /var/local/emhttp "$T/mdcmd.calls"
check "zfs calls" "$(sed '$d' <<<"$DESTROYED")" "$(cat "$T/zfs.calls")"
log_has 'Mover stopped while ZFS dataset [cache/sh] was unmounted: not deleting it, attempting to remount'
log_has 'Not remounting ZFS dataset [cache/sh]: its folder /mnt/cache/sh holds files that a mount would hide'
log_lacks 'successfully destroyed'
check "the dataset is kept, unmounted" yes "$([ -d "$T/zfs.store/cache/sh" ] && echo yes)"
cache_is sh sh/bare.txt
no_private
notices "$NOT_MOUNTED"

# a second stop, at the read of var.ini that puts the write method back, waits for it
begin "Clean ZFS datasets, a second stop as the stopped run puts the write method back" cleanFolders topFolder \
    cleanDatasets yes enableTurbo yes
one_share
mkdir -p /usr/local/sbin /var/local/emhttp
echo 'md_write_method="0"' >/var/local/emhttp/var.ini
printf '#!/bin/bash\necho "mdcmd $*" >>%q\n' "$T/mdcmd.calls" >/usr/local/sbin/mdcmd
chmod 755 /usr/local/sbin/mdcmd
echo $$ >"$T/pid"
cat >"$T/bin/grep" <<EOF
#!/bin/bash
if [ "\$2" = '^md_write_method=' ] && [ -e $T/stop2 ]; then
    rm -f $T/stop2
    p=\$PPID
    while [ "\$(cut -d' ' -f4 /proc/\$p/stat)" != $$ ]; do p=\$(cut -d' ' -f4 /proc/\$p/stat); done
    kill -TERM "\$p"
fi
exec /usr/bin/grep "\$@"
EOF
chmod 755 "$T/bin/grep"
# the run is a subshell of this script: it would keep the grep this script found before
hash -r
{ stop_hook run; echo "touch $T/stop2"; } >"$T/zfs.on_mount.zfs"
run_moves 'processTheMoves did not return'
rm -f "$T/bin/grep"
hash -r
check "the second stop came" "" "$(ls "$T/stop2" 2>/dev/null)"
check "turbo write forced, then put back" "$(printf '%s\n' 'mdcmd set md_write_method 1' 'mdcmd set md_write_method 0')" \
    "$(cat "$T/mdcmd.calls")"
check "the run removed its pid file" "" "$(ls "$T/pid" 2>/dev/null)"
rm -rf /usr/local/sbin/mdcmd /var/local/emhttp "$T/mdcmd.calls"
log_lacks 'successfully destroyed'
no_private

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
notices "$NOT_MOUNTED"

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
begin "Clean ZFS datasets, a stop of the run alone during the next share's checks" cleanFolders topFolder cleanDatasets yes
mk cache a/only/f.txt sh/only/g.txt z/only/h.txt
# the pid file names another run, as after Unraid's mover stop removes it and a new run starts: it stays
echo 1 >"$T/pid"
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
notices "$(notice_for '[cache/a] (not mounted: stop writes to the share, move anything in /mnt/cache/a aside, zfs mount cache/a, then move it back into /mnt/cache/a without replacing a file already there: keep both copies and compare them)')"
no_private
check "another run's pid file stays" 1 "$(cat "$T/pid" 2>/dev/null)"
rm -f "$T/pid"

# a check that fails as a stop comes is still reported
begin "Clean ZFS datasets, a stop of the run alone as the check after the unmount fails" cleanFolders topFolder \
    cleanDatasets yes
one_share
stop_hook run >"$T/zfs.on_mount.zfs"
echo mount.zfs >"$T/zfs.fail"
run_moves 'processTheMoves did not return'
check "zfs calls" "$(grep -vx 'umount PRIVATE' <<<"$REMOUNTED")" "$(cat "$T/zfs.calls")"
log_has "ZFS dataset [cache/sh] could not be checked once unmounted, will not delete: mount: filesystem 'cache/sh' cannot be mounted, zfs.fail"
log_lacks 'Mover stopped while'
mounted_again
no_private
notices "$NOTICE"

# the plugin's stop as the notice goes out: the notice is still sent, then the run ends
begin "Clean ZFS datasets, the plugin's mover stop as the notice goes out" cleanFolders topFolder cleanDatasets yes
one_share
echo unmount >"$T/zfs.fail"
stop_hook plugin >"$NOTIFY_LOG.hook"
run_moves 'processTheMoves did not return'
stop_done
log_has 'Failed to unmount ZFS dataset [cache/sh]'
log_lacks 'top-level'
notices "$NOTICE"

# the plugin's stop as a dataset's notice entry is translated: the translation finishes, so the entry keeps its reason
begin "Clean ZFS datasets, the plugin's mover stop as a dataset's notice entry is translated" cleanFolders topFolder \
    cleanDatasets yes
one_share
echo 'echo x >/mnt/cache/sh/new.txt' >"$T/zfs.on_unmount"
echo mount >"$T/zfs.fail"
stop_hook plugin >"$T/php.hook"
# translate_text runs /usr/bin/php -q translate.php TEMPLATE; this one prints the template back
# shellcheck disable=SC2016 # the stand-in expands its own $3
printf '#!/bin/bash\ncase $3 in "not mounted:"*) [ ! -f %q ] || bash %q ;; esac\nprintf %%s "$3"\n' "$T/php.hook" "$T/php.hook" \
    >/usr/bin/php
chmod 755 /usr/bin/php
run_moves 'processTheMoves did not return'
rm -f /usr/bin/php
stop_done
check "the stop came during the translation" "" "$(ls "$T/php.hook" 2>/dev/null)"
log_has 'Failed to remount dataset [cache/sh]'
notices "$NOT_MOUNTED"

# a run that starts as the stopped one ends writes its own pid file, which the plugin's stop then leaves
begin "Clean ZFS datasets, the plugin's mover stop, and another run starts as the stopped one ends" cleanFolders topFolder \
    cleanDatasets yes
one_share
{ stop_hook plugin; echo "echo 1 >\"$T/pid\""; } >"$T/zfs.on_unmount"
run_moves 'processTheMoves did not return'
for _ in $(seq 100); do grep -qs 'mover: stopped' "$T/stop.out" && break; sleep 0.1; done
check "the plugin's stop ended" 1 "$(grep -cs 'mover: stopped' "$T/stop.out")"
check "the other run's pid file stays" 1 "$(cat "$T/pid" 2>/dev/null)"
rm -f "$T/stop.out" "$T/pid"
mounted_again

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
    # a stop after the kill ends the run once the dataset is back; the cut-short check is still reported
    [[ $when != *mover* ]] || log_lacks 'top-level'
    if [[ $when == *fails ]]; then
        notices "$(read_only_notice "$private")"
        log_has "ZFS dataset [cache/sh] is still mounted read-only at $private, not at /mnt/cache/sh: umount: $private: zfs.fail"
        log_has "ZFS dataset [cache/sh]: mounted read-only at $private: stop writes to the share, umount $private, $BACK"
        check "the dataset stays at the private folder" "$private"$'\t'cache/sh "$(cat "$T/zfs.private")"
        continue
    fi
    notices "$NOTICE"
    log_has 'ZFS dataset [cache/sh] could not be checked once unmounted, will not delete: the check was cut short'
    mounted_again
    no_private
done

# a scan's subshell killed outright, its caller not: it printed nothing because it never looked. The first check keeps
# the dataset mounted; the one at the private mount, where a file landed as it unmounted, keeps it and mounts it back
SCAN=". -mindepth 1 -path ./.zfs -prune -o ! -type d -print -quit"
for which in 'first check' 'check at the private mount'; do
    begin "Clean ZFS datasets, the scan of the $which is killed" cleanFolders topFolder cleanDatasets yes
    one_share
    wrap_hook find "$SCAN"
    if [ "$which" = 'first check' ]; then
        kill_hook KILL : >"$T/find.hook"
    else
        kill_hook KILL : 1 >"$T/kill.hook"
        printf '%s\n' 'echo x >/mnt/cache/sh/new.txt' "cp \"$T/kill.hook\" \"$T/find.hook\"" >"$T/zfs.on_unmount"
    fi
    PATH=$T/wrap:$PATH run_moves
    log_lacks 'successfully destroyed'
    if [ "$which" = 'first check' ]; then
        check "zfs calls" "zfs $LS cache/sh" "$(cat "$T/zfs.calls")"
        log_lacks 'attempting to unmount'
        notices ''
        continue
    fi
    check "zfs calls" "$REMOUNTED" "$(cat "$T/zfs.calls")"
    log_has 'ZFS dataset [cache/sh] could not be checked once unmounted, will not delete: the check was cut short'
    notices "$NOTICE"
    mounted_again
    cache_is sh sh/new.txt
    no_private
done

# a file lands in the folder as the dataset is mounted back. The look after the mount killed printed nothing because it
# never looked; the whole remount killed leaves the run unable to tell whether the mount happened
# Notify errors only: a failure still sends the notice, which alone carries the steps when action logging is off
for what in look remount; do
    begin "Clean ZFS datasets, the $what at the mount back is killed" cleanFolders topFolder cleanDatasets yes notify errorsOnly
    one_share
    echo 'echo x >/mnt/cache/sh/new.txt' >"$T/zfs.on_unmount"
    echo 'echo y >/mnt/cache/sh/late.txt' >"$T/zfs.on_mount"
    wrap_hook find ". -mindepth 1 -print -quit"
    if [ "$what" = look ]; then
        cat >"$T/find.hook" <<'EOF'
rm -f "$0"
kill -KILL "$PPID"
EOF
    else
        kill_hook KILL : >"$T/find.hook"
    fi
    PATH=$T/wrap:$PATH run_moves
    check "zfs calls" "$REMOUNTED" "$(cat "$T/zfs.calls")"
    if [ "$what" = look ]; then
        why="mounted again, but the look for a file written to /mnt/cache/sh as it was mounted was cut short, so one may be hidden under it: stop writes to the share, zfs unmount cache/sh, $BACK"
    else
        why="the remount was cut short, so it may not be mounted or may hide a file: stop writes to the share, if zfs mount lists it at /mnt/cache/sh run zfs unmount cache/sh, $BACK"
    fi
    log_has "ZFS dataset [cache/sh]: $why"
    log_lacks 'Failed to remount'
    notices "$(notice_for "[cache/sh] ($why)")"
    mounted_again
    cache_is sh sh/new.txt
    no_private
done

finish
