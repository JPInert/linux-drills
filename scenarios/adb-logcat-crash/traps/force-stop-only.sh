# bounces the app but the permission is still revoked: it crashes again straight away
adb shell am force-stop com.facility.camerad
sleep 3
adb shell "ps -A | grep camerad" || true
