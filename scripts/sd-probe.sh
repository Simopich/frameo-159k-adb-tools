#!/system/bin/sh
# Diagnostic only: read Android state and write results to the removable card.
# Do not invoke su, install software, change settings, or restart services.
probe_dir=${0%/*}
case "$probe_dir" in
    /storage/*) ;;
    *) exit 10 ;;
esac
[ -d "$probe_dir/Frameo_utilities" ] || exit 11
[ -f "$probe_dir/frameo-159k-probe.done" ] && exit 0

{
    printf '%s\n' 'Frameo 159K SD diagnostic v1' '--- execution identity ---'
    id
    printf '%s\n' '--- device properties ---'
    for probe_prop in \
        ro.product.model ro.product.brand ro.board.platform ro.hardware \
        ro.product.cpu.abi ro.build.version.release ro.build.version.sdk \
        ro.build.display.id ro.build.fingerprint ro.adb.secure \
        init.svc.adbd service.adb.tcp.port persist.adb.tcp.port; do
        printf '%s=' "$probe_prop"
        getprop "$probe_prop"
    done
    printf '%s\n' '--- running Frameo package ---'
    dumpsys package net.frameo.frame | grep -m 1 'versionCode='
    dumpsys package net.frameo.frame | grep -m 1 'versionName='
    printf '%s\n' '--- su location; su is not executed ---'
    command -v su || :
    for probe_su in /system/bin/su /system/xbin/su /sbin/su /su/bin/su; do
        if [ -e "$probe_su" ]; then ls -l "$probe_su"; fi
    done
    printf '%s\n' '--- SELinux ---'
    if command -v getenforce >/dev/null 2>&1; then getenforce; fi
    printf '%s\n' '--- complete: diagnostic reads only; output on removable card ---'
} > "$probe_dir/frameo-159k-probe.txt" 2>&1 || exit 12
printf '%s\n' 'complete' > "$probe_dir/frameo-159k-probe.done"
