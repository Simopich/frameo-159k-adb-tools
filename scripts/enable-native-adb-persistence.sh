#!/system/bin/sh
# Use the firmware's existing authenticated network-ADB hook. Never reboot.
set -e
[ "$(id -u)" = 0 ] || exit 10
[ "$(getprop ro.product.model)" = 159K ] || exit 11
[ "$(getprop ro.board.platform)" = rk3326 ] || exit 12
[ "$(getprop ro.build.version.sdk)" = 27 ] || exit 13
[ "$(getprop ro.build.display.id)" = RK3326_8.1_AY_FRAMEO_202511241509 ] || exit 14
[ "$(getprop ro.build.fingerprint)" = rockchip/rk3326_evb/rk3326_evb:8.1.0/OC/150829:user/release-keys ] || exit 15
[ "$(getprop ro.adb.secure)" = 1 ] || exit 16
grep -F -q 'on property:persist.internet.adb.enable=1' /init.rk30board.rc || exit 17
setprop persist.adb.tcp.port 5555
[ "$(getprop persist.adb.tcp.port)" = 5555 ] || exit 18
setprop persist.internet.adb.enable 1
# This property invokes the vendor init rule and may disconnect the ADB session.
