#!/bin/bash
# What processTheMoves does today when a soft stop or a pause comes before or between its rows.
. "$(dirname "$0")/lib.sh"

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

finish
