#!/bin/bash
# shellcheck disable=SC1091,SC2034 # lib.sh is sourced from this folder and reads CASE
# The plg's post-install step on a saved config, taken from the real plg by xmllint, a real XML parser, on Unraid
# 7.2.1, with the plugin's files copied in place; php and update_cron are stand-ins. PLG=<file> runs another plg. The step's
# pgrep finds age_mover in this test's paths, so it always takes its "run in progress" branch and keeps /var/run's files.
. "$(dirname "$0")/lib.sh"
PLG=$(realpath "${PLG:-$HERE/../../plugins/ca.mover.tuning.plg}")
CFG=/boot/config/plugins/ca.mover.tuning/ca.mover.tuning.cfg
STANDINS=(/usr/bin/php /usr/local/sbin/update_cron)
# the step writes under /boot, /usr/local and /var/run, and the test writes /usr/bin/php and /etc/unraid-version: a mount at
# one (Unraid's flash drive) refuses, and so does a php or update_cron this test did not write
if ! awk '$5 ~ "^/(boot|usr/local)(/|$)" || $5 ~ "^/(usr(/bin(/php)?)?|var|etc(/unraid-version)?|(var/)?run)$" { exit 1 }' /proc/self/mountinfo; then
    echo "test_install.sh writes Unraid's paths and one is a mount here: start it with tests/age_mover/run.sh" >&2
    exit 2
fi
for f in "${STANDINS[@]}"; do
    [ ! -e "$f" ] || grep -qx '# test_install.sh stand-in' "$f" || { echo "test_install.sh: $f is not this test's stand-in" >&2; exit 2; }
done
trap 'rm -rf /boot/config /usr/local/emhttp/plugins/ca.mover.tuning /usr/local/sbin/age_mover /etc/unraid-version "${STANDINS[@]}"' EXIT

xmllint --noent --xpath 'string(//comment()[contains(., "The '\''post-install'\'' script")]/following-sibling::FILE[1]/INLINE)' "$PLG" \
    >"$T/post_install.sh"
if ! grep -q 'Updating config file' "$T/post_install.sh"; then
    echo "test_install.sh: no post-install step read from $PLG" >&2
    exit 2
fi
VERSION=$(xmllint --noent --xpath 'string(/PLUGIN/@version)' "$PLG")
for f in "${STANDINS[@]}"; do
    # shellcheck disable=SC2016 # the stand-in expands its own name and arguments
    printf '#!/bin/bash\n# test_install.sh stand-in\necho "${0##*/}${*:+ $*}" >>%q\n' "$T/install.calls" >"$f"
    chmod 755 "$f"
done
echo 'version="7.2.1"' >/etc/unraid-version
rm -rf /usr/local/emhttp/plugins/ca.mover.tuning
mkdir -p /usr/local/emhttp/plugins
cp -r "$PLUGIN" /usr/local/emhttp/plugins/

# run_step <case> <line end> <line>...: the step on a saved config of these lines, each ending in <line end> and \n; its output
# is the log
run_step() {
    CASE=$1
    local eol=$2 rc
    shift 2
    rm -rf /boot/config "$T/install.calls"
    mkdir -p "${CFG%/*}"
    printf "%s$eol\n" "$@" >"$CFG"
    (cd "$T/cwd" && bash "$T/post_install.sh") >"$MOVER_LOG" 2>"$T/err"
    rc=$?
    check "the step exited 0" 0 "$rc"
    check "stderr held nothing" "" "$(cat "$T/err")"
    check "the step ran to its end: php and update_cron were called" \
        "$(printf '%s\n' 'php -q /usr/local/emhttp/plugins/ca.mover.tuning/updateCron.php sync' update_cron)" "$(cat "$T/install.calls" 2>/dev/null)"
}
# cfg_is <line end> <line>...: the config holds exactly these lines besides version=, which every install sets to the plg's
# version, and testmode=, which a major upgrade sets
cfg_is() {
    local eol=$1
    shift
    check "the config holds exactly $*" "$(printf "%s$eol\n" "$@" | cat -A)" "$(grep -vE '^(version|testmode)=' "$CFG" | cat -A)"
    check "version is the plg's" "version=\"$VERSION\"" "$(grep '^version=' "$CFG" | tr -d '\r')"
}
REMOVING="- Removing the old filename check's settings"

run_step "both keys among other keys" '' 'logging="yes"' 'validateFilenames="yes"' 'movenow="yes"' \
    'invalidFileChars="$ / < > : \" | ? *"' 'version="2026.01.01"' 'movingThreshold="80"' 'freeingThreshold="70"' 'migratedOverrideNo="yes"'
cfg_is '' 'logging="yes"' 'movenow="yes"' 'movingThreshold="80"' 'freeingThreshold="70"' 'migratedOverrideNo="yes"'
log_has "$REMOVING"

run_step "a CRLF file" '\r' 'logging="yes"' 'invalidFileChars="*"' 'movenow="yes"' 'validateFilenames="no"' 'version="2026.01.01"' \
    'movingThreshold="80"' 'freeingThreshold="70"' 'migratedOverrideNo="yes"'
cfg_is '\r' 'logging="yes"' 'movenow="yes"' 'movingThreshold="80"' 'freeingThreshold="70"' 'migratedOverrideNo="yes"'
log_has "$REMOVING"

run_step "validateFilenamesOld beside invalidFileChars" '' 'validateFilenamesOld="x"' 'invalidFileChars="*"' 'version="2026.01.01"' \
    'movingThreshold="80"' 'freeingThreshold="70"' 'migratedOverrideNo="yes"'
cfg_is '' 'validateFilenamesOld="x"' 'movingThreshold="80"' 'freeingThreshold="70"' 'migratedOverrideNo="yes"'
log_has "$REMOVING"

# debug_mover sources the config: a backtick saved in invalidFileChars stopped it there, so every key below stayed empty
run_step "a backtick in invalidFileChars" '' 'logging="yes"' 'invalidFileChars="`"' 'movenow="yes"' 'version="2026.01.01"' \
    'movingThreshold="80"' 'freeingThreshold="70"' 'migratedOverrideNo="yes"'
cfg_is '' 'logging="yes"' 'movenow="yes"' 'movingThreshold="80"' 'freeingThreshold="70"' 'migratedOverrideNo="yes"'
check "the config sources to its end, with nothing on stderr" 'movenow=yes' "$(bash -c '. "$1"; echo "movenow=$movenow"' _ "$CFG" 2>&1)"

run_step "neither key, only validateFilenamesOld" '' 'logging="yes"' 'validateFilenamesOld="x"' 'version="2026.01.01"' \
    'movingThreshold="80"' 'freeingThreshold="70"' 'migratedOverrideNo="yes"'
cfg_is '' 'logging="yes"' 'validateFilenamesOld="x"' 'movingThreshold="80"' 'freeingThreshold="70"' 'migratedOverrideNo="yes"'
log_lacks "$REMOVING"

finish
