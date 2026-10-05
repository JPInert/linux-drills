# the classic: adb says "already connected" and the stale offline entry survives
adb connect 10.50.0.77:5555 || true
adb devices || true
