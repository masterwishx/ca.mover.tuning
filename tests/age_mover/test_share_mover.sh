#!/bin/bash
# shellcheck disable=SC1091,SC2034 # lib.sh is sourced from this folder and reads CASE
# The per-share Move: the real share_mover on share sh, with Unraid's config files as each case writes them under /boot and
# /var/local/emhttp, lib.sh's move stand-in and an mdcmd stand-in. SM=<file> runs another copy of share_mover.
. "$(dirname "$0")/lib.sh"
SM=$(realpath "${SM:-$PLUGIN/share_mover}") # run starts it from $T/cwd
CFG=/boot/config/plugins/ca.mover.tuning/ca.mover.tuning.cfg
# the cases write under /boot, /var/local and /usr/local, and /var/run/mover.pid: a mount at one (Unraid's flash drive) refuses
if ! awk '$5 ~ "^/(boot|var/local|usr/local)(/|$)" || $5 ~ "^/(var|usr|(var/)?run(/mover\\.pid)?)$" { exit 1 }' /proc/self/mountinfo; then
    echo "test_share_mover.sh writes Unraid's paths and one is a mount here: start it with tests/age_mover/run.sh" >&2
    exit 2
fi
mkdir -p /usr/local/sbin
cat >/usr/local/sbin/mdcmd <<EOF
#!/bin/bash
echo "mdcmd \$*" >>$T/mdcmd.calls
EOF
chmod 755 /usr/local/sbin/mdcmd

# share <case> <shareUseCache> [key value]...: share sh on pool cache, two pools, and the shipped plugin defaults with these keys
# changed; the value - removes the key
share() {
    CASE=$1
    local use=$2
    shift 2
    rm -rf "${ROOTS[@]}" /boot/config /var/local/emhttp /var/run/mover.pid "$T/mdcmd.calls"
    mkdir -p /mnt/cache /mnt/user0 /mnt/disk1 /boot/config/plugins/ca.mover.tuning /boot/config/shares /boot/config/pools /var/local/emhttp
    printf '%s\n' 'shareCacheEnabled="yes"' 'shareMoverLogging="yes"' >/boot/config/share.cfg
    printf '%s\n' 'NAME="Tower"' 'timeZone="UTC"' >/boot/config/ident.cfg
    printf '%s\n' "shareUseCache=\"$use\"" 'shareCachePool="cache"' >/boot/config/shares/sh.cfg
    : >/boot/config/pools/cache.cfg
    : >/boot/config/pools/fast.cfg
    printf '%s\n' 'md_write_method="auto"' >/var/local/emhttp/var.ini
    cp "$PLUGIN/default.cfg" "$CFG"
    while [ $# -ge 2 ]; do
        grep -q "^$1=" "$CFG" || { echo "share: $1 is not in default.cfg" >&2; exit 2; }
        if [ "$2" = - ]; then sed -i "/^$1=/d" "$CFG"; else sed -i "s|^$1=.*|$1=\"$2\"|" "$CFG"; fi
        shift 2
    done
}

# bg <argv0> <command>...: the command in the background under that name, once it has replaced the forked test script, whose
# path holds "mover" too
bg() {
    local a0
    (exec -a "$1" "${@:2}") &
    for _ in {1..100}; do
        read -r -d '' a0 <"/proc/$!/cmdline"
        [ "$a0" = "$1" ] && return
        sleep 0.05
    done
    echo "bg: $1 did not start" >&2
    exit 2
}

# run <exit status> [stderr]: share_mover sh (or $NAME), its output without mvlogger's date as the log; stderr must be exactly the given
# text, nothing by default
run() {
    local rc
    (cd "$T/cwd" && bash "$SM" "${NAME:-sh}") >"$T/out" 2>"$T/err"
    rc=$?
    sed -E 's/^[A-Z][a-z]{2} [ 0-9][0-9] [0-9:]{8} Share mover: //' "$T/out" >"$MOVER_LOG"
    check "share_mover exited $1" "$1" "$rc"
    check "stderr held $([ -n "${2:-}" ] && echo only the expected text || echo nothing)" "${2:-}" "$(cat "$T/err")"
}
mdcmd_calls() { check "mdcmd calls: ${*:-none}" "$( (($#)) && printf 'mdcmd %s\n' "$@")" "$(cat "$T/mdcmd.calls" 2>/dev/null)"; }
# move_hook <command>: Unraid's move runs the command first, until move_unhook
move_hook() {
    mv /usr/libexec/unraid/move "$T/move.real"
    cat >/usr/libexec/unraid/move <<EOF
#!/bin/bash
$1
exec "$T/move.real" "\$@"
EOF
    chmod 755 /usr/libexec/unraid/move
}
move_unhook() { mv "$T/move.real" /usr/libexec/unraid/move; }

share 'a yes share in test mode' yes testmode yes version 2026.01.02
mk cache sh/d/a.txt
run 0
log_has 'Running in Test Mode: find "/mnt/cache/sh" -type f -depth'
log_has '/mnt/cache/sh/d/a.txt'
check 'the title line' '***************************************************** Mover Tuning Plugin version 2026.01.02 ****************************************************' \
    "$(grep -F 'Plugin version' "$MOVER_LOG")"
check 'the last line' '****************************************************************** WE ARE DONE ! ****************************************************************' \
    "$(tail -n 1 "$MOVER_LOG")"
cache_is sh sh/d sh/d/a.txt
array_is
mdcmd_calls

share 'a yes share' yes
mk cache sh/d/a.txt sh/b.txt
run 0
log_has 'Complete Mover Command: find "/mnt/cache/sh" -type f -depth | /usr/libexec/unraid/move -d 1'
log_count 2 'Success'
cache_is sh sh/d
array_is sh sh/b.txt sh/d sh/d/a.txt
mdcmd_calls

share 'no move at /usr/libexec/unraid, so the one in PATH' yes
mk cache sh/a.txt
mv /usr/libexec/unraid/move "$T/move.aside"
cp "$T/move.aside" "$T/bin/move"
run 0
mv "$T/move.aside" /usr/libexec/unraid/move
rm "$T/bin/move"
log_has "Complete Mover Command: find \"/mnt/cache/sh\" -type f -depth | $T/bin/move -d 1"
array_is sh sh/a.txt

share 'a prefer share' prefer
mk disk1 sh/c.txt
mk user0 sh/u.txt
run 0
log_has 'Complete Mover Command: find "/mnt/disk1/sh" "/mnt/user0/sh" -type f -not -path /mnt/user\* -depth | /usr/libexec/unraid/move -d 1'
cache_is sh sh/c.txt
holds disk1 sh
array_is sh sh/u.txt

for wm in 'auto Auto (read/modify/write)' '1 Turbo writes (Reconstruct)' '0 Read/modify/write'; do
    share "turbo on, md_write_method ${wm%% *}" yes enableTurbo yes
    printf 'md_write_method="%s"\n' "${wm%% *}" >/var/local/emhttp/var.ini
    mk cache sh/a.txt
    run 0
    log_has 'Forcing turbo write on'
    log_has "Restoring original turbo write mode ${wm#* }"
    mdcmd_calls 'set md_write_method 1' "set md_write_method ${wm%% *}"
    array_is sh sh/a.txt
done

share 'turbo on in test mode' yes enableTurbo yes testmode yes
mk cache sh/a.txt
run 0
log_has 'TEST MODE: Would force turbo write on'
log_has 'TEST MODE: Would restore original turbo write mode Auto (read/modify/write)'
log_lacks 'Forcing turbo write on'
log_lacks 'Restoring original turbo write mode'
mdcmd_calls
cache_is sh sh/a.txt

share 'turbo on, var.ini gives no write method' yes enableTurbo yes
: >/var/local/emhttp/var.ini
mk cache sh/a.txt
run 0
log_has 'Not forcing turbo write on: /var/local/emhttp/var.ini gives no write method (0, 1 or auto) to set back after'
log_lacks 'Restoring original turbo write mode'
mdcmd_calls
array_is sh sh/a.txt

# a save in Settings during the moves changes var.ini's write method: that one is set back, or the one read before
# when var.ini then gives none
for now in '0 Read/modify/write' ' Auto (read/modify/write)'; do
    share "turbo on, var.ini gives \"${now%% *}\" during the moves" yes enableTurbo yes
    mk cache sh/a.txt
    move_hook "echo 'md_write_method=\"${now%% *}\"' >/var/local/emhttp/var.ini"
    run 0
    move_unhook
    w=${now%% *}
    mdcmd_calls 'set md_write_method 1' "set md_write_method ${w:-auto}"
    log_count 1 "Restoring original turbo write mode ${now#* }"
    array_is sh sh/a.txt
done

# a stop of the run during the moves: it ends once the move does, and sets the write method back before its pid file goes
share 'turbo on, a stop during the moves' yes enableTurbo yes
mk cache sh/a.txt
# shellcheck disable=SC2016 # the hook expands it
move_hook 'kill -TERM "$(cat /var/run/mover.pid)"'
cat >/usr/local/sbin/mdcmd <<EOF
#!/bin/bash
w=\$(cat /var/run/mover.pid 2>/dev/null)
echo "mdcmd \$*\${w:+ (pid file there)}" >>$T/mdcmd.calls
EOF
run 143
move_unhook
mdcmd_calls 'set md_write_method 1 (pid file there)' 'set md_write_method auto (pid file there)'
log_count 1 'Restoring original turbo write mode Auto (read/modify/write)'
check 'the run removed its pid file' '' "$(ls /var/run/mover.pid 2>/dev/null)"
array_is sh sh/a.txt
cat >/usr/local/sbin/mdcmd <<EOF
#!/bin/bash
echo "mdcmd \$*" >>$T/mdcmd.calls
EOF

# a share name with shell in it is a name: the run moves its files and runs nothing
share 'a share name that holds a command' yes
# shellcheck disable=SC2016 # the name holds shell text on purpose
n='a $(touch ran)'
mv /boot/config/shares/sh.cfg "/boot/config/shares/$n.cfg"
mk cache "$n/b.txt"
NAME=$n run 0
log_has "Complete Mover Command: find \"/mnt/cache/$n\" -type f -depth | /usr/libexec/unraid/move -d 1"
check 'the name ran nothing' no "$([ -e "$T/cwd/ran" ] && echo yes || echo no)"
array_is "$n" "$n/b.txt"

share 'no enableTurbo or testmode in the plugin config' yes enableTurbo - testmode -
mk cache sh/a.txt
run 0
log_has 'No Turbo Mode argument provided, defaulting to no'
log_has 'No Test Mode argument provided, defaulting to yes'
log_has 'Running in Test Mode'
check 'enableTurbo="no" was written to the plugin config, testmode was not' 'enableTurbo="no"' "$(grep -E '^(enableTurbo|testmode)=' "$CFG")"
cache_is sh sh/a.txt

share 'another mover runs' yes
mk cache sh/a.txt
bg mover sleep 30
echo $! >/var/run/mover.pid
run 1
kill $! 2>/dev/null
wait $! 2>/dev/null
log_has 'already running'
log_lacks 'Processing sh share'
cache_is sh sh/a.txt

share 'the pid file holds the running mover with spaces, then a second line' yes
mk cache sh/a.txt
bg mover sleep 30
printf ' %s \n99999999\n' $! >/var/run/mover.pid
run 1
kill $! 2>/dev/null
wait $! 2>/dev/null
log_has 'already running'
cache_is sh sh/a.txt

share 'the pid file names a process that is no mover' yes
mk cache sh/a.txt
bg sleep sleep 30
echo $! >/var/run/mover.pid
run 0
kill $! 2>/dev/null
wait $! 2>/dev/null
log_lacks 'already running'
array_is sh sh/a.txt

share 'an empty pid file' yes
mk cache sh/a.txt
: >/var/run/mover.pid
run 0
log_lacks 'already running'
array_is sh sh/a.txt

share 'no share.cfg' yes
rm /boot/config/share.cfg
mk cache sh/a.txt
run 2
check 'nothing was logged' '' "$(cat "$MOVER_LOG")"
cache_is sh sh/a.txt

share 'no plugin config' yes
rm "$CFG"
mk cache sh/a.txt
run 3
log_has "Fatal error: $CFG does not exist, check this."
log_lacks 'Plugin version'
cache_is sh sh/a.txt

for pools in 1 0; do
    share "$pools pool config(s), and no /mnt/user0 mount" yes
    rm /boot/config/pools/fast.cfg
    [ "$pools" = 1 ] || rm -r /boot/config/pools
    mk cache sh/a.txt
    run 5
    log_has 'Fatal error: cache not present, or only cache present, and less than 2 pools set up.'
    cache_is sh sh/a.txt
done

rm -rf "${ROOTS[@]}" /boot/config /var/local/emhttp /var/run/mover.pid /usr/local/sbin/mdcmd
finish
