#!/system/bin/sh
# Read-only source collection; writes only into a new temporary backup directory.
set -eu
set -o pipefail
dest=$1
case "$dest" in /data/local/tmp/frameo-backup-*) ;; *) exit 10 ;; esac
tag=${dest#/data/local/tmp/}
suffix=${tag#frameo-backup-}
case "$suffix" in ''|*[!A-Za-z0-9_-]*) exit 11 ;; esac
photo_mode=${3:-include}
case "$photo_mode" in include|exclude) ;; *) exit 18 ;; esac
[ "$(id -u)" = 0 ] || exit 12
[ "$(getprop ro.product.model)" = 159K ] || exit 13
[ "$(getprop ro.build.display.id)" = RK3326_8.1_AY_FRAMEO_202511241509 ] || exit 14
[ ! -e "$dest" ] || exit 15
mkdir "$dest"
chmod 700 "$dest"
mkdir "$dest/metadata" "$dest/apks" "$dest/partitions"
printf '%s\n' "$tag" > "$dest/OWNER_MARKER"

echo 'Checking tar exclusion before collecting userdata.'
testdir="$dest/exclusion-input"
mkdir -p "$testdir/local/tmp/$tag"
printf '%s\n' keep > "$testdir/keep.txt"
printf '%s\n' exclude > "$testdir/local/tmp/$tag/exclude.txt"
printf '%s\n' "./local/tmp/$tag" > "$dest/exclusion-patterns.txt"
tar -X "$dest/exclusion-patterns.txt" -czf "$dest/exclusion-test.tar.gz" -C "$testdir" .
tar -tzf "$dest/exclusion-test.tar.gz" > "$dest/exclusion-test.list"
grep -q 'keep.txt' "$dest/exclusion-test.list" || exit 16
if grep -q 'exclude.txt' "$dest/exclusion-test.list"; then exit 17; fi
rm "$testdir/local/tmp/$tag/exclude.txt" "$testdir/keep.txt"
rmdir "$testdir/local/tmp/$tag" "$testdir/local/tmp" "$testdir/local" "$testdir"
rm "$dest/exclusion-test.tar.gz" "$dest/exclusion-test.list" "$dest/exclusion-patterns.txt"

echo 'Saving private inventory and configuration exports.'
getprop > "$dest/metadata/properties.txt"
pm list packages -f -U -i > "$dest/metadata/packages.txt"
pm list packages -d > "$dest/metadata/disabled-packages.txt"
pm list packages -s > "$dest/metadata/system-packages.txt"
pm list packages -3 > "$dest/metadata/third-party-packages.txt"
dumpsys package > "$dest/metadata/packages-dump.txt"
dumpsys activity activities > "$dest/metadata/activities-before.txt"
for namespace in global secure system; do
    settings list "$namespace" > "$dest/metadata/settings-$namespace.txt"
done
mount > "$dest/metadata/mounts.txt"
cat /proc/partitions > "$dest/metadata/proc-partitions.txt"
ls -l /dev/block/by-name > "$dest/metadata/partition-links.txt"
df -k > "$dest/metadata/filesystems.txt"
ls -lnRZ /data/data /data/user_de /data/system /data/misc /oem /vendor/frameo \
    > "$dest/metadata/ownership-selinux.txt" 2> "$dest/metadata/ownership-selinux-errors.txt" || :
printf 'partition\tbytes\tstart_sector\tsectors\n' > "$dest/metadata/partition-layout.tsv"
for link in /dev/block/by-name/*; do
    name=${link##*/}
    block=$(readlink -f "$link")
    node=${block##*/}
    bytes=$(blockdev --getsize64 "$link")
    start=$(cat "/sys/class/block/$node/start")
    sectors=$(cat "/sys/class/block/$node/size")
    printf '%s\t%s\t%s\t%s\n' "$name" "$bytes" "$start" "$sectors" >> "$dest/metadata/partition-layout.tsv"
done

echo 'Copying every APK, including updated and factory Frameo copies.'
find /system /vendor /oem /data/app /data/app-private -type f -name '*.apk' \
    > "$dest/metadata/apk-source-paths.txt"
printf 'source\tbytes\tsha256\n' > "$dest/metadata/apks.tsv"
while IFS= read -r source; do
    relative=${source#/}
    target="$dest/apks/$relative"
    mkdir -p "${target%/*}"
    before=$(sha256sum "$source")
    before=${before%% *}
    cp "$source" "$target"
    copied=$(sha256sum "$target")
    copied=${copied%% *}
    after=$(sha256sum "$source")
    after=${after%% *}
    [ "$before" = "$copied" ] && [ "$after" = "$copied" ] || exit 20
    bytes=$(stat -c '%s' "$target")
    printf '%s\t%s\t%s\n' "$source" "$bytes" "$copied" >> "$dest/metadata/apks.tsv"
done < "$dest/metadata/apk-source-paths.txt"

echo 'Capturing root filesystem configuration and OEM customization files.'
: > "$dest/metadata/root-file-paths.txt"
for source in /init*.rc /fstab* /default.prop /ueventd*.rc; do
    if [ -e "$source" ] || [ -L "$source" ]; then
        printf '%s\n' "${source#/}" >> "$dest/metadata/root-file-paths.txt"
    fi
done
tar -czf "$dest/root-files.tar.gz" -C / -T "$dest/metadata/root-file-paths.txt"
: > "$dest/metadata/customization-paths.txt"
for source in /vendor/frameo /vendor/overlay /oem /metadata /system/etc; do
    if [ -d "$source" ]; then printf '%s\n' "${source#/}" >> "$dest/metadata/customization-paths.txt"; fi
done
tar -czf "$dest/customizations.tar.gz" -C / -T "$dest/metadata/customization-paths.txt" \
    2> "$dest/metadata/customizations-tar-stderr.txt"

echo 'Pausing Frameo for its private-data and shared-media snapshot.'
restore_activity=${2:-net.frameo.frame/.ui.activities.AFirstScreen}
case "$restore_activity" in net.frameo.frame/*) ;; *) exit 21 ;; esac
paused=0
restore_frameo() {
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$paused" = 1 ]; then
        am start -n "$restore_activity" > "$dest/metadata/frameo-resume.txt" 2>&1 || :
    fi
    exit "$result"
}
trap restore_frameo EXIT
trap 'exit 130' HUP INT TERM
am force-stop net.frameo.frame
paused=1
printf '%s\n' \
    "./local/tmp/$tag" './dalvik-cache' './resource-cache' './cache' \
    './anr' './tombstones' './logs' './trace_thread.log' './misc/logd' \
    > "$dest/metadata/userdata-exclusions.txt"
if [ "$photo_mode" = exclude ]; then
    printf '%s\n' './media/0/frameo_files/media' './media/0/frameo_files/profilePictures' \
        './media/0/frameo_files/videoThumbnails' './media/0/frameo_files/cache' \
        './media/0/Pictures' './media/0/DCIM' './media/0/Movies' \
        './data/net.frameo.frame/cache' './data/net.frameo.frame/code_cache' \
        >> "$dest/metadata/userdata-exclusions.txt"
fi
printf '%s\n' "$photo_mode" > "$dest/metadata/personal-photo-policy.txt"
find /data -type s > "$dest/metadata/volatile-ipc-paths.txt"
find /data -type p >> "$dest/metadata/volatile-ipc-paths.txt"
while IFS= read -r volatile; do
    printf '.%s\n' "${volatile#/data}" >> "$dest/metadata/userdata-exclusions.txt"
done < "$dest/metadata/volatile-ipc-paths.txt"
tar -X "$dest/metadata/userdata-exclusions.txt" \
    -czf "$dest/userdata.tar.gz" -C /data . 2> "$dest/metadata/userdata-tar-stderr.txt"
am start -n "$restore_activity" > "$dest/metadata/frameo-resume.txt" 2>&1
paused=0
trap - EXIT HUP INT TERM

echo 'Saving recovery partitions; userdata and cache are not imaged.'
printf 'partition\traw_bytes\traw_sha256\n' > "$dest/metadata/raw-partition-hashes.tsv"
for name in uboot trust misc resource kernel boot recovery backup security system vendor oem metadata frp; do
    block="/dev/block/by-name/$name"
    [ -b "$block" ] || continue
    echo "Reading partition: $name"
    expected=$(blockdev --getsize64 "$block")
    raw="$dest/partitions/$name.img"
    dd if="$block" of="$raw" bs=1048576 2> "$dest/metadata/dd-$name.txt"
    actual=$(stat -c '%s' "$raw")
    [ "$actual" = "$expected" ] || exit 22
    raw_hash=$(sha256sum "$raw")
    raw_hash=${raw_hash%% *}
    printf '%s\t%s\t%s\n' "$name" "$actual" "$raw_hash" >> "$dest/metadata/raw-partition-hashes.tsv"
    gzip -1 -c "$raw" > "$raw.gz"
    rm "$raw"
done

echo 'Building device-side checksums.'
printf '%s\n' 'Source collection completed; host verification is still required.' > "$dest/COLLECTION_COMPLETE"
cd "$dest"
find . -type f ! -name SHA256SUMS -print | sort > /data/local/tmp/"$tag"-hash-input.txt
while IFS= read -r file; do sha256sum "$file"; done \
    < /data/local/tmp/"$tag"-hash-input.txt > SHA256SUMS
rm /data/local/tmp/"$tag"-hash-input.txt
echo 'Granting the authenticated ADB shell read-only access to staged copies.'
chgrp -R 2000 "$dest"
find "$dest" -type d -exec chmod 750 {} \;
find "$dest" -type f -exec chmod 640 {} \;
echo "Device collection ready: $dest"
