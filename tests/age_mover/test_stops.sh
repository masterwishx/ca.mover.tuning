#!/bin/bash
# What processTheMoves does today when a stop, a soft stop or a pause comes before or between its rows.
. "$(dirname "$0")/lib.sh"
# a case writes under /usr/local and /var/local: a mount at either refuses
if ! awk '$5 ~ "^/(usr|var)/local(/|$)" || $5 ~ "^/(usr|var)$" { exit 1 }' /proc/self/mountinfo; then
    echo "test_stops.sh writes Unraid's paths and one is a mount here: start it with tests/age_mover/run.sh" >&2
    exit 2
fi

HELPERS=()
# after_pause <s> <command>...: in the background, runs the command <s> s after the run logs its pause; begin removed
# the last case's log
after_pause() {
    local s=$1
    shift
    (until grep -qF 'Paused: no file moves until Resume' "$MOVER_LOG" 2>/dev/null; do sleep 0.1; done; sleep "$s"; "$@") >/dev/null 2>&1 &
    HELPERS+=($!)
}
held() { log | sed -n 's/.*Resumed after \([0-9]*\) s.*/\1/p'; }
# must run before the next case: a helper left running would lift or stop that case's pause
stop_helpers() {
    kill "${HELPERS[@]}" 2>/dev/null
    wait "${HELPERS[@]}" 2>/dev/null
    HELPERS=()
}
order() { log | grep -oE 'Moving "[^"]*"|Paused: no file moves until Resume|Resumed after|Soft Stopping requested'; }

begin "soft stop after the first file" synchronizeCache yes
mk cache sh/s/1.txt sh/s/2.txt sh/s/3.txt
{ row 'move from primary' f sh/s/1.txt; row 'move from primary' f sh/s/2.txt; row 'sync from primary' f sh/s/3.txt; } | list
after_first_rsync "touch '$SOFTSTOPFILE'"
run_moves
array_is sh sh/s sh/s/1.txt
cache_is sh sh/s sh/s/2.txt sh/s/3.txt
counter MOVEDFILES 1
check "the order of the moves and the soft stop" "$(printf '%s\n' 'Moving "/mnt/cache/./sh/s/1.txt"' 'Soft Stopping requested')" "$(order)"
log_lacks 'Set last sync date'

# processTheMoves returns at its start, before its banner; its row loop would also hold the file at the first row
begin "soft stop before the run"
mk cache sh/s/1.txt
row 'move from primary' f sh/s/1.txt | list
touch "$SOFTSTOPFILE"
run_moves
array_is
cache_is sh sh/s sh/s/1.txt
check "the order of the moves and the soft stop" 'Soft Stopping requested' "$(order)"
log_lacks 'LET THE MOVING SHOW BEGIN'

begin "pause after the first file, lifted 2 s later"
mk cache sh/s/1.txt sh/s/2.txt
for n in 1 2; do row 'move from primary' f "sh/s/$n.txt"; done | list
after_first_rsync "echo $$ >'$PAUSEFILE'"
after_pause 2 rm -f "$PAUSEFILE"
run_moves
stop_helpers
array_is sh sh/s sh/s/1.txt sh/s/2.txt
counter MOVEDFILES 2
check "the order of the moves and the pause" "$(printf '%s\n' 'Moving "/mnt/cache/./sh/s/1.txt"' 'Paused: no file moves until Resume' \
    'Resumed after' 'Moving "/mnt/cache/./sh/s/2.txt"')" "$(order)"
check "the pause held from 2 s to under 10 s" yes "$([ "$(held)" -ge 2 ] 2>/dev/null && [ "$(held)" -lt 10 ] && echo yes || echo no)"

# the lift only ends a pause the run should not have taken, so a broken check fails instead of hanging
begin "a pause file naming another run"
mk cache sh/s/1.txt
row 'move from primary' f sh/s/1.txt | list
echo 1 >"$PAUSEFILE"
after_pause 2 rm -f "$PAUSEFILE"
run_moves
stop_helpers
array_is sh sh/s sh/s/1.txt
log_lacks 'Paused'

begin "soft stop 2 s into a pause before the first file"
mk cache sh/s/1.txt
row 'move from primary' f sh/s/1.txt | list
echo $$ >"$PAUSEFILE"
after_pause 2 touch "$SOFTSTOPFILE"
after_pause 20 rm -f "$PAUSEFILE"
run_moves
stop_helpers
array_is
cache_is sh sh/s sh/s/1.txt
check "the order of the moves, the pause and the soft stop" "$(printf '%s\n' 'Paused: no file moves until Resume' 'Resumed after' \
    'Soft Stopping requested')" "$(order)"
check "the pause held under 10 s: the soft stop ended it, not the 20 s lift" yes "$([ "$(held)" -lt 10 ] 2>/dev/null && echo yes || echo no)"

# Unraid's write method, read/modify/write, and an mdcmd that notes its calls
turbo_standin() {
    mkdir -p /usr/local/sbin /var/local/emhttp
    echo 'md_write_method="0"' >/var/local/emhttp/var.ini
    printf '#!/bin/bash\necho "mdcmd $*" >>%q\n' "$T/mdcmd.calls" >/usr/local/sbin/mdcmd
    chmod 755 /usr/local/sbin/mdcmd
}
put_back_once() {
    check "turbo write forced, then put back once" "$(printf '%s\n' 'mdcmd set md_write_method 1' 'mdcmd set md_write_method 0')" \
        "$(cat "$T/mdcmd.calls")"
    log_count 1 'Restoring original turbo write mode Read/modify/write'
    rm -rf /usr/local/sbin/mdcmd /var/local/emhttp "$T/mdcmd.calls"
}

begin "turbo write on, no stop" enableTurbo yes
mk cache sh/s/1.txt
row 'move from primary' f sh/s/1.txt | list
turbo_standin
run_moves
put_back_once
array_is sh sh/s sh/s/1.txt

# a stop that ends the run during the moves: the run puts back the write method it forced. The plugin's stop also
# signals the hook, which ignores it, so the rsync wrapper ends by the signal and not by reporting a failed hook
for who in plugin run; do
    begin "turbo write on, a stop ($who) after the first file" enableTurbo yes
    mk cache sh/s/1.txt sh/s/2.txt
    for n in 1 2; do row 'move from primary' f "sh/s/$n.txt"; done | list
    turbo_standin
    if [ "$who" = plugin ]; then after_first_rsync "trap '' TERM; $(stop_hook plugin)"; else after_first_rsync "$(stop_hook run)"; fi
    run_moves 'processTheMoves did not return'
    if [ "$who" = plugin ]; then
        for _ in $(seq 100); do grep -qs 'mover: stopped' "$T/stop.out" && break; sleep 0.1; done
        check "the plugin's stop ended" 1 "$(grep -cs 'mover: stopped' "$T/stop.out")"
        rm -f "$T/stop.out"
    fi
    put_back_once
    array_is sh sh/s sh/s/1.txt
    cache_is sh sh/s sh/s/2.txt
done

# a second stop, at the read of var.ini that puts the write method back, waits for it
begin "turbo write on, a second stop as the run puts it back" enableTurbo yes
mk cache sh/s/1.txt sh/s/2.txt
for n in 1 2; do row 'move from primary' f "sh/s/$n.txt"; done | list
turbo_standin
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
after_first_rsync "touch $T/stop2
$(stop_hook run)"
run_moves 'processTheMoves did not return'
rm -f "$T/bin/grep"
hash -r
check "the second stop came" "" "$(ls "$T/stop2" 2>/dev/null)"
put_back_once
array_is sh sh/s sh/s/1.txt
cache_is sh sh/s sh/s/2.txt

# the plugin's stop signals mdcmd before the run, so mdcmd can end before it sets the write method back (143 here): the
# run keeps its EXIT trap and tries again as it ends
begin "turbo write on, mdcmd fails as the run puts the write method back" enableTurbo yes
mk cache sh/s/1.txt
row 'move from primary' f sh/s/1.txt | list
turbo_standin
touch "$T/fail_once"
cat >/usr/local/sbin/mdcmd <<EOF
#!/bin/bash
[ "\$3" != 0 ] || [ ! -e $T/fail_once ] || { rm -f $T/fail_once; exit 143; }
echo "mdcmd \$*" >>$T/mdcmd.calls
EOF
run_moves
check "turbo write forced, then put back as the run ended" "$(printf '%s\n' 'mdcmd set md_write_method 1' \
    'mdcmd set md_write_method 0')" "$(cat "$T/mdcmd.calls")"
log_count 1 'Could not restore original turbo write mode Read/modify/write: mdcmd exited 143'
log_count 2 'Restoring original turbo write mode Read/modify/write'
rm -rf /usr/local/sbin/mdcmd /var/local/emhttp "$T/mdcmd.calls"
array_is sh sh/s sh/s/1.txt

begin "turbo write on, mdcmd fails to force it" enableTurbo yes
mk cache sh/s/1.txt
row 'move from primary' f sh/s/1.txt | list
turbo_standin
cat >/usr/local/sbin/mdcmd <<EOF
#!/bin/bash
[ "\$3" != 1 ] || exit 1
echo "mdcmd \$*" >>$T/mdcmd.calls
EOF
run_moves
check "the write method was set back as it was" 'mdcmd set md_write_method 0' "$(cat "$T/mdcmd.calls")"
log_count 1 'Could not force turbo write on: mdcmd exited 1'
log_count 1 'Restoring original turbo write mode Read/modify/write'
rm -rf /usr/local/sbin/mdcmd /var/local/emhttp "$T/mdcmd.calls"
array_is sh sh/s sh/s/1.txt

begin "turbo write on, var.ini gives no write method" enableTurbo yes
mk cache sh/s/1.txt
row 'move from primary' f sh/s/1.txt | list
turbo_standin
: >/var/local/emhttp/var.ini
run_moves
check "mdcmd was not called" "" "$(cat "$T/mdcmd.calls" 2>/dev/null)"
log_has 'Not forcing turbo write on: /var/local/emhttp/var.ini gives no write method (0, 1 or auto) to set back after'
log_lacks 'Restoring original turbo write mode'
rm -rf /usr/local/sbin/mdcmd /var/local/emhttp "$T/mdcmd.calls"
array_is sh sh/s sh/s/1.txt

begin "turbo write on, in test mode" enableTurbo yes testmode yes
mk cache sh/s/1.txt
row 'move from primary' f sh/s/1.txt | list
turbo_standin
run_moves
check "mdcmd was not called" "" "$(cat "$T/mdcmd.calls" 2>/dev/null)"
log_has 'TEST MODE: Would force turbo write on'
log_has 'TEST MODE: Would restore original turbo write mode Read/modify/write'
log_lacks 'Forcing turbo write on'
log_lacks 'Restoring original turbo write mode'
rm -rf /usr/local/sbin/mdcmd /var/local/emhttp "$T/mdcmd.calls"
cache_is sh sh/s sh/s/1.txt

# a save in Settings during the moves changes var.ini's write method: that one is set back, or the one read before
# when var.ini then gives none
for now in 'auto Auto (read/modify/write)' ' Read/modify/write'; do
    begin "turbo write on, var.ini gives \"${now%% *}\" during the moves" enableTurbo yes
    mk cache sh/s/1.txt
    row 'move from primary' f sh/s/1.txt | list
    turbo_standin
    after_first_rsync "echo 'md_write_method=\"${now%% *}\"' >/var/local/emhttp/var.ini"
    run_moves
    w=${now%% *}
    check "turbo write forced, then set back to ${w:-0}" "$(printf '%s\n' 'mdcmd set md_write_method 1' \
        "mdcmd set md_write_method ${w:-0}")" "$(cat "$T/mdcmd.calls")"
    log_count 1 "Restoring original turbo write mode ${now#* }"
    rm -rf /usr/local/sbin/mdcmd /var/local/emhttp "$T/mdcmd.calls"
    array_is sh sh/s sh/s/1.txt
done

# a process pgrep lists can end before its TERM, or between its TERM and CONT: a pid no process can have stands for the
# first, so no real one is signalled, and a kill that waits after each TERM until its process has gone for the second
begin "the plugin's stop, listed processes that end before or between its signals"
real_pgrep=$(command -v pgrep)
# this script waits on the run, so it is reaped as it ends: one nobody reaps would still answer the stop's kill -0
bash -c 'sleep 30 && exit 3' &
run=$!
gone=$(($(cat /proc/sys/kernel/pid_max) + 1))
# shellcheck disable=SC2016 # the stand-in expands its own $@ and $*
printf '#!/bin/bash\n%q "$@"\n[ "${*: -1}" != %q ] || echo %q\n' "$real_pgrep" "$run" "$gone" >"$T/bin/pgrep"
chmod 755 "$T/bin/pgrep"
hash -r
echo "$run" >"$T/pid"
# shellcheck disable=SC2034,SC2329 # stop, from funcs.sh, reads the variables and calls kill
(
    kill() {
        builtin kill "$@" || return
        [ "$1" = -TERM ] || return 0
        for _ in $(seq 50); do builtin kill -0 "$2" 2>/dev/null || return 0; sleep 0.1; done
    }
    PIDFILE=$T/pid MOVER_STATUS=$T/mover.ini PAUSEFILE=$T/pause MOVINGFILE=$T/moving
    stop
) >"$T/stop.out" 2>&1 &
stopper=$!
wait "$run"
check "the stop ended the run" 143 "$?"
wait "$stopper"
rm -f "$T/bin/pgrep"
hash -r
check "the stop said only that it stopped" 'mover: stopped' "$(cat "$T/stop.out")"
check "the stop removed the pid file" "" "$(ls "$T/pid" 2>/dev/null)"
rm -f "$T/stop.out"

finish
