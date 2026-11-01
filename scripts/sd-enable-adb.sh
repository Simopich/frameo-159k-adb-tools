#!/system/bin/sh
# Enable temporary, authenticated Wi-Fi ADB on the exact probed 159K firmware.
# Never change ro.adb.secure or the persistent TCP port.
card=${0%/*}
case "$card" in /storage/*) ;; *) exit 10 ;; esac
state="$card/frameo-159k-adb"
[ -d "$state" ] || exit 11
[ -f "$state/done" ] && exit 0
[ -e "$state/started" ] && exit 12
exec > "$state/result.txt" 2>&1 || exit 13

die() { printf 'ERROR: %s\n' "$*"; exit 1; }
printf '%s\n' 'Frameo 159K authenticated temporary ADB v1'
[ "$(id -u)" = 0 ] || die 'Root execution required.'
[ "$(getprop ro.product.model)" = 159K ] || die 'Wrong model.'
[ "$(getprop ro.board.platform)" = rk3326 ] || die 'Wrong platform.'
[ "$(getprop ro.build.version.sdk)" = 27 ] || die 'Wrong Android API.'
[ "$(getprop ro.build.display.id)" = RK3326_8.1_AY_FRAMEO_202511241509 ] || die 'Wrong firmware build.'
[ "$(getprop ro.build.fingerprint)" = rockchip/rk3326_evb/rk3326_evb:8.1.0/OC/150829:user/release-keys ] || die 'Wrong firmware fingerprint.'
[ "$(getprop ro.adb.secure)" = 1 ] || die 'ADB authentication must already be enabled.'

IFS= read -r public_line < "$state/adbkey.pub" || die 'Cannot read public key.'
public_blob=${public_line%% *}
[ "${#public_blob}" = 700 ] || die 'Wrong public key length.'
case "$public_blob" in QAAAA*=) ;; *) die 'Wrong ADB public key prefix or suffix.' ;; esac
case "$public_blob" in *[!A-Za-z0-9+/=]*) die 'Invalid base64 characters.' ;; esac
[ "$(wc -l < "$state/adbkey.pub" | tr -d '[:space:]')" = 1 ] || die 'Expected one public key line.'

key_dir=/data/misc/adb
key_file="$key_dir/adb_keys"
stage_file="$key_dir/adb_keys.frameo-local.tmp"
for guarded_path in /data /data/misc "$key_dir" "$key_file" "$stage_file"; do
    [ ! -L "$guarded_path" ] || die "Symlink refused: $guarded_path"
done
[ -d /data/misc ] || die 'Missing Android data directory.'
[ ! -e "$stage_file" ] || die 'Staging path already exists.'
if [ -e "$key_dir" ] && [ ! -d "$key_dir" ]; then die 'ADB path is not a directory.'; fi
if [ -e "$key_file" ] && [ ! -f "$key_file" ]; then die 'ADB key path is not a regular file.'; fi

had_dir=0
[ -d "$key_dir" ] && had_dir=1
had_key=0
old_uid=
old_gid=
old_mode=
if [ -f "$key_file" ]; then
    had_key=1
    old_uid=$(stat -c '%u' "$key_file") || die 'Cannot read key owner.'
    old_gid=$(stat -c '%g' "$key_file") || die 'Cannot read key group.'
    old_mode=$(stat -c '%a' "$key_file") || die 'Cannot read key mode.'
    case "$old_uid:$old_gid:$old_mode" in *[!0-9:]*|::*|*::*) die 'Invalid key metadata.' ;; esac
    [ -n "$old_uid" ] && [ -n "$old_gid" ] && [ -n "$old_mode" ] || die 'Empty key metadata.'
    cp "$key_file" "$state/adb_keys.before" || die 'Cannot back up keys.'
    cmp -s "$key_file" "$state/adb_keys.before" || die 'Key backup differs.'
fi
old_port=$(getprop service.adb.tcp.port) || die 'Cannot read TCP port.'
old_persist=$(getprop persist.adb.tcp.port) || die 'Cannot read persistent TCP port.'
old_daemon=$(getprop init.svc.adbd) || die 'Cannot read adbd state.'
case "$old_daemon" in running|stopped) ;; *) die 'Unstable adbd baseline.' ;; esac
printf '%s\n' "$had_dir" > "$state/directory.before" || die 'Cannot record baseline.'
printf '%s\n' "$had_key" > "$state/keys.before.state" || die 'Cannot record baseline.'
printf '%s:%s:%s\n' "$old_uid" "$old_gid" "$old_mode" > "$state/keys.before.metadata" || die 'Cannot record metadata.'
printf '%s\n' "$old_port" > "$state/service-port.before" || die 'Cannot record baseline.'
printf '%s\n' "$old_persist" > "$state/persist-port.before" || die 'Cannot record baseline.'
printf '%s\n' "$old_daemon" > "$state/adbd.before" || die 'Cannot record baseline.'

if [ "$had_key" = 1 ]; then
    cp "$state/adb_keys.before" "$state/adb_keys.candidate" || die 'Cannot prepare keys.'
else
    : > "$state/adb_keys.candidate" || die 'Cannot prepare keys.'
fi
if ! grep -F -q "$public_blob" "$state/adb_keys.candidate"; then
    printf '\n%s\n' "$public_line" >> "$state/adb_keys.candidate" || die 'Cannot append public key.'
fi
if [ "$had_key" = 1 ]; then
    cmp -s "$key_file" "$state/adb_keys.before" || die 'Key baseline changed; refusing replacement.'
else
    [ ! -e "$key_file" ] || die 'Key file appeared; refusing replacement.'
fi
[ "$(getprop service.adb.tcp.port)" = "$old_port" ] || die 'TCP port baseline changed.'
[ "$(getprop persist.adb.tcp.port)" = "$old_persist" ] || die 'Persistent port baseline changed.'
[ "$(getprop init.svc.adbd)" = "$old_daemon" ] || die 'adbd baseline changed.'

changed=0
key_installed=0
created_dir=0
staged=0
rollback() {
    printf '%s\n' 'Attempting rollback.'
    rollback_ok=1
    setprop service.adb.tcp.port "$old_port" || rollback_ok=0
    if [ "$key_installed" = 1 ]; then
        if [ "$had_key" = 1 ]; then
            cp "$state/adb_keys.before" "$stage_file" &&
                chown "$old_uid:$old_gid" "$stage_file" && chmod "$old_mode" "$stage_file" &&
                mv "$stage_file" "$key_file" || rollback_ok=0
            if command -v restorecon >/dev/null 2>&1; then restorecon "$key_file" || rollback_ok=0; fi
            cmp -s "$key_file" "$state/adb_keys.before" || rollback_ok=0
            [ "$(stat -c '%u:%g:%a' "$key_file")" = "$old_uid:$old_gid:$old_mode" ] || rollback_ok=0
        else
            rm -f "$key_file" || rollback_ok=0
            [ ! -e "$key_file" ] || rollback_ok=0
        fi
    fi
    if [ "$staged" = 1 ] && [ -f "$stage_file" ]; then rm -f "$stage_file" || rollback_ok=0; fi
    if [ "$created_dir" = 1 ]; then rmdir "$key_dir" || rollback_ok=0; fi
    stop adbd || rollback_ok=0
    if [ "$old_daemon" = running ]; then start adbd || rollback_ok=0; fi
    sleep 1
    [ "$(getprop service.adb.tcp.port)" = "$old_port" ] || rollback_ok=0
    [ "$(getprop persist.adb.tcp.port)" = "$old_persist" ] || rollback_ok=0
    [ "$(getprop init.svc.adbd)" = "$old_daemon" ] || rollback_ok=0
    if [ "$rollback_ok" = 1 ]; then
        printf '%s\n' 'Rollback verified.'
    else
        printf '%s\n' 'ROLLBACK INCOMPLETE: inspect saved baseline before another attempt.'
    fi
}
finish() {
    finish_status=$?
    trap - EXIT HUP INT TERM
    if [ "$finish_status" -ne 0 ] && [ "$changed" = 1 ]; then rollback; fi
    exit "$finish_status"
}
trap finish EXIT
trap 'exit 130' HUP INT TERM
printf '%s\n' 'started' > "$state/started" || die 'Cannot write one-shot marker.'
changed=1
if [ "$had_dir" = 0 ]; then
    mkdir "$key_dir" || die 'Cannot create ADB directory.'
    created_dir=1
    chown 1000:2000 "$key_dir" && chmod 750 "$key_dir" || die 'Cannot set ADB directory permissions.'
    if command -v restorecon >/dev/null 2>&1; then restorecon "$key_dir" || die 'Cannot label ADB directory.'; fi
fi
staged=1
cp "$state/adb_keys.candidate" "$stage_file" || die 'Cannot stage keys.'
chown 1000:2000 "$stage_file" && chmod 640 "$stage_file" || die 'Cannot set key permissions.'
cmp -s "$stage_file" "$state/adb_keys.candidate" || die 'Staged keys differ.'
if [ "$had_key" = 1 ]; then
    cmp -s "$key_file" "$state/adb_keys.before" || die 'Keys changed during staging.'
else
    [ ! -e "$key_file" ] || die 'Key file appeared during staging.'
fi
key_installed=1
mv "$stage_file" "$key_file" || die 'Cannot publish keys.'
if command -v restorecon >/dev/null 2>&1; then restorecon "$key_file" || die 'Cannot label keys.'; fi
cmp -s "$key_file" "$state/adb_keys.candidate" || die 'Published keys differ.'
[ "$(stat -c '%a' "$key_file")" = 640 ] || die 'Wrong key permissions.'
[ "$(getprop ro.adb.secure)" = 1 ] || die 'Authentication changed.'
setprop service.adb.tcp.port 5555 || die 'Cannot set temporary TCP port.'
[ "$(getprop service.adb.tcp.port)" = 5555 ] || die 'TCP property did not stick.'
stop adbd || die 'Cannot stop adbd.'
start adbd || die 'Cannot start adbd.'
attempt=0
listening=0
while [ "$attempt" -lt 10 ]; do
    if grep -E -q '[[:xdigit:]]+:15B3[[:space:]]+[[:xdigit:]]+:[[:xdigit:]]+[[:space:]]+0A[[:space:]]' /proc/net/tcp /proc/net/tcp6; then
        listening=1
        break
    fi
    sleep 1
    attempt=$((attempt + 1))
done
[ "$listening" = 1 ] || die 'No TCP 5555 listener appeared.'
[ "$(getprop init.svc.adbd)" = running ] || die 'adbd is not running.'
[ "$(getprop ro.adb.secure)" = 1 ] || die 'Authentication check failed.'
[ "$(getprop persist.adb.tcp.port)" = "$old_persist" ] || die 'Persistent TCP port changed unexpectedly.'
printf '%s\n' 'Local checks passed: adbd running, TCP 5555 listening, ro.adb.secure=1.'
printf '%s\n' 'The PC must still verify authenticated ADB access. Persistence across reboot is not configured.'
if [ -f "$card/Frameo_utilities/frameo_utilities.config" ]; then
    mv "$card/Frameo_utilities/frameo_utilities.config" "$state/frameo_utilities.config.used" || die 'Cannot retire SD trigger.'
fi
printf '%s\n' 'complete' > "$state/done" || die 'Cannot write completion marker.'
changed=0
exit 0
