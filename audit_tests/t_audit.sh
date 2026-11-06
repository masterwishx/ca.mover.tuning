#!/bin/bash
# Audit repros through the real age_mover, with_scripts, mover.php and moverProgress.php.
# Only Unraid's mover and its move tool are stand-ins (no Unraid in the container).
P=/usr/local/emhttp/plugins/ca.mover.tuning
# install this worktree's plugin files at their real path
if [ ! -x "$P/age_mover" ]; then
    mkdir -p /usr/local/emhttp/plugins
    cp -r "$(cd "$(dirname "$0")/.." && pwd)/source/ca.mover.tuning/usr/local/emhttp/plugins/ca.mover.tuning" /usr/local/emhttp/plugins/
fi
AM=${AGE_MOVER:-$P/age_mover}
T=$(mktemp -d)
mkdir -p "$T/bin" "$T/src"
for i in 1 2 3 4 5 6 7 8; do echo "$i" >"$T/src/f$i"; done
# stand-in move (7.3.4 shape: one move reads every file from find); 1 s per file
cat >"$T/bin/move" <<EOF
#!/bin/bash
while read -r f; do sleep 1; echo "\$f" >>"$T/moved.\$PPID"; done
EOF
# stand-in Unraid mover: writes the pid file, find | move, removes the pid file at its end
cat >"$T/bin/mover" <<EOF
#!/bin/bash
echo \$\$ >/var/run/mover.pid
trap 'rm -f /var/run/mover.pid' EXIT
find "$T/src" -type f | "$T/bin/move"
EOF
chmod +x "$T/bin/move" "$T/bin/mover"
pass=0 fail=0
check() { if eval "$2"; then echo "ok   $1"; pass=$((pass + 1)); else echo "FAIL $1"; echo "     $3"; fail=$((fail + 1)); fi; }
waitpid() { for _ in $(seq 50); do [ -s /var/run/mover.pid ] && return 0; sleep 0.1; done; return 1; }
state() { awk '{print $3}' "/proc/$1/stat" 2>/dev/null; }
clean() { pkill -f "age_mover holdmoves" 2>/dev/null; pkill -x move 2>/dev/null; pkill -f "$T/bin/mover" 2>/dev/null; sleep 0.3
    rm -f /var/run/mover.pid /var/run/mover.pause /var/run/mover.moving /var/run/moversoft.stop; }
clean

# A1: a paused wrapped run stopped by Unraid 7.4's mover stop (TERM to the run only, 2 s, KILL) leaves mover.pause;
# the next wrapped run is then reported paused while nothing holds it
$P/with_scripts "$T/bin/mover" start </dev/null >/dev/null 2>&1 &
waitpid; run1=$(cat /var/run/mover.pid)
out=$($AM pause); sleep 1.5
check "A1 instrument: run 1 paused" '[ "$out" = "mover: paused" ]' "pause said: $out"
kill -TERM "$run1"; sleep 2; kill -KILL "$run1" 2>/dev/null; rm -f /var/run/mover.pid; sleep 1.5
check "A1 keeper gone after the run" '! pgrep -f "age_mover holdmoves" >/dev/null' "keeper still there"
check "A1 no pause file once the paused run is gone" '[ ! -e /var/run/mover.pause ]' "mover.pause left behind: $(ls -l /var/run/mover.pause 2>&1)"
pkill -x move; sleep 0.2
$P/with_scripts "$T/bin/mover" start </dev/null >/dev/null 2>&1 &
waitpid; run2=$(cat /var/run/mover.pid); sleep 2.5
mv2=$(pgrep -x move | head -1)
prog=$(php $P/moverProgress.php 2>/dev/null)
check "A1 run 2: its move runs (instrument)" '[ "$(state "$mv2")" != T ]' "move state $(state "$mv2")"
check "A1 run 2 not reported paused while it moves" '[[ "$prog" != *"\"paused\":true"* ]]' "moverProgress.php: $prog; move $mv2 state $(state "$mv2"); moved so far: $(wc -l <"$T/moved.$run2" 2>/dev/null)"
wdog=$(grep -c . /dev/null)
clean

# A2: mover.php softstop on a wrapped run (now routed to age_mover) leaves moversoft.stop after the run ends,
# and the next wrapped run cannot be paused
$P/with_scripts "$T/bin/mover" start </dev/null >/dev/null 2>&1 &
waitpid; run3=$(cat /var/run/mover.pid)
# mover.php softstop passthrus exactly this (mover.php:259-262); its dynamix include is absent here
sout=$($AM softstop 2>&1 | tail -1)
for _ in $(seq 150); do kill -0 "$run3" 2>/dev/null || break; sleep 0.1; done
check "A2 instrument: run 3 ended by itself" '! kill -0 "$run3" 2>/dev/null' "run still alive"
n3=$(wc -l <"$T/moved.$run3" 2>/dev/null)
check "A2 soft stop: the wrapped run stops after its current file (softstop's comment, age_mover:3462)" '[ "${n3:-0}" -le 2 ]' "the run moved $n3 of 8 files after the soft stop"
check "A2 no soft stop file once the run is gone" '[ ! -e /var/run/moversoft.stop ]' "moversoft.stop left behind (softstop said: $sout)"
$P/with_scripts "$T/bin/mover" start </dev/null >/dev/null 2>&1 &
waitpid; sleep 0.5
pout=$($AM pause)
check "A2 the next wrapped run can be paused" '[ "$pout" = "mover: paused" ]' "pause said: $pout; moverProgress.php: $(php $P/moverProgress.php 2>/dev/null)"
clean

rm -rf "$T"
echo "audit: $pass passed, $fail failed"
[ "$fail" = 0 ]
