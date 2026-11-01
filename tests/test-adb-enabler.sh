#!/usr/bin/env bash
# Exercise the production shell logic against isolated files and mocked Android commands.
# Only this test copy has Android absolute paths replaced by workspace paths.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$repo/work"
test_root=$(mktemp -d "$repo/work/adb-enabler-test.XXXXXX")
mkdir "$test_root/bin"
cat > "$test_root/mock" <<'MOCK'
#!/usr/bin/env bash
set -eu
command_name=${0##*/}
case "$command_name" in
    id) printf '%s\n' 0 ;;
    getprop) if [ -f "$CASE_ROOT/props/$1" ]; then cat "$CASE_ROOT/props/$1"; fi ;;
    setprop)
        if [ "${FAIL_PORT:-0}" = 1 ] && [ "$2" = 5555 ]; then exit 1; fi
        [ "$1" = service.adb.tcp.port ] || { printf '%s\n' 'Unexpected property write' >&2; exit 1; }
        printf '%s\n' "$2" > "$CASE_ROOT/props/$1"
        ;;
    stop) printf '%s\n' stopped > "$CASE_ROOT/props/init.svc.adbd"; : > "$CASE_ROOT/proc/net/tcp" ;;
    start)
        printf '%s\n' running > "$CASE_ROOT/props/init.svc.adbd"
        if [ "$(cat "$CASE_ROOT/props/service.adb.tcp.port")" = 5555 ] && [ "${FAIL_LISTEN:-0}" != 1 ]; then
            printf '%s\n' ' 0: 00000000:15B3 00000000:0000 0A 00000000:00000000' > "$CASE_ROOT/proc/net/tcp"
        fi
        ;;
    chown)
        if [ "${FAIL_CHOWN:-0}" = 1 ]; then exit 1; fi
        inode=$(/usr/bin/stat -c '%i' "$2")
        printf '%s\n' "$1" > "$CASE_ROOT/owners/$inode"
        ;;
    chmod)
        /usr/bin/chmod "$@"
        inode=$(/usr/bin/stat -c '%i' "$2")
        printf '%s\n' "$1" > "$CASE_ROOT/modes/$inode"
        ;;
    stat)
        inode=$(/usr/bin/stat -c '%i' "$3")
        if [ -f "$CASE_ROOT/owners/$inode" ]; then
            owner=$(cat "$CASE_ROOT/owners/$inode")
        else
            owner=$(/usr/bin/stat -c '%u:%g' "$3")
        fi
        if [ -f "$CASE_ROOT/modes/$inode" ]; then
            mode=$(cat "$CASE_ROOT/modes/$inode")
        else
            mode=$(/usr/bin/stat -c '%a' "$3")
        fi
        case "$2" in
            '%u') printf '%s\n' "${owner%:*}" ;;
            '%g') printf '%s\n' "${owner#*:}" ;;
            '%a') printf '%s\n' "$mode" ;;
            '%u:%g:%a') printf '%s:%s\n' "$owner" "$mode" ;;
            *) /usr/bin/stat "$@" ;;
        esac
        ;;
    restorecon|sleep) : ;;
    *) exit 90 ;;
esac
MOCK
for tool in id getprop setprop stop start chown chmod stat restorecon sleep; do
    cp "$test_root/mock" "$test_root/bin/$tool"
    chmod +x "$test_root/bin/$tool"
done

prepare_case() {
    case_name=$1
    export CASE_ROOT="$test_root/$case_name"
    export FAIL_LISTEN=0 FAIL_PORT=0 FAIL_CHOWN=0
    mkdir -p "$CASE_ROOT/props" "$CASE_ROOT/modes" "$CASE_ROOT/owners" "$CASE_ROOT/data/misc" "$CASE_ROOT/storage/card/frameo-159k-adb" \
        "$CASE_ROOT/storage/card/Frameo_utilities" "$CASE_ROOT/proc/net"
    card="$CASE_ROOT/storage/card"
    state="$card/frameo-159k-adb"
    key_file="$CASE_ROOT/data/misc/adb/adb_keys"
    printf '%s\n' 159K > "$CASE_ROOT/props/ro.product.model"
    printf '%s\n' rk3326 > "$CASE_ROOT/props/ro.board.platform"
    printf '%s\n' 27 > "$CASE_ROOT/props/ro.build.version.sdk"
    printf '%s\n' RK3326_8.1_AY_FRAMEO_202511241509 > "$CASE_ROOT/props/ro.build.display.id"
    printf '%s\n' rockchip/rk3326_evb/rk3326_evb:8.1.0/OC/150829:user/release-keys > "$CASE_ROOT/props/ro.build.fingerprint"
    printf '%s\n' 1 > "$CASE_ROOT/props/ro.adb.secure"
    printf '%s\n' running > "$CASE_ROOT/props/init.svc.adbd"
    : > "$CASE_ROOT/props/service.adb.tcp.port"
    : > "$CASE_ROOT/props/persist.adb.tcp.port"
    : > "$CASE_ROOT/proc/net/tcp"
    : > "$CASE_ROOT/proc/net/tcp6"
    printf '%s\n' auto_run=action_update_version > "$card/Frameo_utilities/frameo_utilities.config"
    public_blob=$(printf 'QAAAA%0694d=' 0)
    printf '%s frameo-test\n' "$public_blob" > "$state/adbkey.pub"
    sed -e "s|/data|$CASE_ROOT/data|g" -e "s|/storage|$CASE_ROOT/storage|g" \
        -e "s|/proc/net|$CASE_ROOT/proc/net|g" "$repo/scripts/sd-enable-adb.sh" > "$card/p_frameo_jb"
}

run_case() {
    result=0
    PATH="$test_root/bin:$PATH" bash "$card/p_frameo_jb" || result=$?
}
assert_success() {
    [ "$result" = 0 ]
    [ -f "$state/done" ]
    [ "$(cat "$CASE_ROOT/props/service.adb.tcp.port")" = 5555 ]
    [ ! -s "$CASE_ROOT/props/persist.adb.tcp.port" ]
    [ "$(cat "$CASE_ROOT/props/ro.adb.secure")" = 1 ]
    grep -Fq "$public_blob" "$key_file"
    [ ! -e "$card/Frameo_utilities/frameo_utilities.config" ]
    [ ! -e "$CASE_ROOT/data/misc/adb/adb_keys.frameo-local.tmp" ]
}
assert_rollback() {
    [ "$result" != 0 ]
    [ ! -e "$state/done" ]
    [ -z "$(cat "$CASE_ROOT/props/service.adb.tcp.port")" ]
    [ -z "$(cat "$CASE_ROOT/props/persist.adb.tcp.port")" ]
    grep -Fq 'Rollback verified.' "$state/result.txt"
    [ ! -e "$CASE_ROOT/data/misc/adb/adb_keys.frameo-local.tmp" ]
}

prepare_case existing_keys
mkdir -p "$(dirname "$key_file")"
printf '%s\n' previous-key > "$key_file"
PATH="$test_root/bin:$PATH" chmod 600 "$key_file"
run_case; assert_success
grep -Fxq previous-key "$key_file"
grep -Fxq previous-key "$state/adb_keys.before"
printf '%s\n' 'PASS: preserve existing keys and enable authenticated temporary ADB'
before=$(sha256sum "$key_file")
run_case; [ "$result" = 0 ]; [ "$before" = "$(sha256sum "$key_file")" ]
printf '%s\n' 'PASS: successful run is one-shot'

prepare_case empty_keys
mkdir -p "$(dirname "$key_file")"; : > "$key_file"
run_case; assert_success
[ -f "$state/adb_keys.before" ] && [ ! -s "$state/adb_keys.before" ]
printf '%s\n' 'PASS: empty key file baseline'

prepare_case no_directory
run_case; assert_success
printf '%s\n' 'PASS: absent ADB directory baseline'

prepare_case wrong_fingerprint
printf '%s\n' different > "$CASE_ROOT/props/ro.build.fingerprint"
run_case
[ "$result" != 0 ] && [ ! -e "$state/started" ] && [ ! -d "$CASE_ROOT/data/misc/adb" ]
[ ! -s "$CASE_ROOT/props/service.adb.tcp.port" ]
printf '%s\n' 'PASS: reject unprobed firmware before configuration changes'

prepare_case listener_failure_existing
mkdir -p "$(dirname "$key_file")"; printf '%s\n' previous-key > "$key_file"; PATH="$test_root/bin:$PATH" chmod 600 "$key_file"
export FAIL_LISTEN=1
run_case; assert_rollback
cmp -s "$key_file" "$state/adb_keys.before"
[ "$(PATH="$test_root/bin:$PATH" stat -c '%a' "$key_file")" = 600 ]
[ "$(cat "$CASE_ROOT/props/init.svc.adbd")" = running ]
printf '%s\n' 'PASS: listener failure restores existing keys, mode, ports and daemon'

prepare_case listener_failure_absent
export FAIL_LISTEN=1
run_case; assert_rollback
[ ! -d "$CASE_ROOT/data/misc/adb" ]
printf '%s\n' 'PASS: listener failure restores absent directory and key baseline'

prepare_case property_failure
mkdir -p "$(dirname "$key_file")"; printf '%s\n' previous-key > "$key_file"; PATH="$test_root/bin:$PATH" chmod 600 "$key_file"
export FAIL_PORT=1
run_case; assert_rollback
cmp -s "$key_file" "$state/adb_keys.before"
printf '%s\n' 'PASS: property write failure rolls back authorization changes'

prepare_case permission_failure
export FAIL_CHOWN=1
run_case; assert_rollback
[ ! -d "$CASE_ROOT/data/misc/adb" ]
printf '%s\n' 'PASS: permission failure cleans up the created directory'

prepare_case stopped_daemon_failure
printf '%s\n' stopped > "$CASE_ROOT/props/init.svc.adbd"
export FAIL_LISTEN=1
run_case; assert_rollback
[ "$(cat "$CASE_ROOT/props/init.svc.adbd")" = stopped ]
printf '%s\n' 'PASS: rollback restores a stopped adbd baseline'
printf 'Test evidence retained at %s\n' "$test_root"
