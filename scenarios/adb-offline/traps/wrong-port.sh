# server restarted, but the hub is added on the wrong port
adb kill-server; adb start-server
adb connect 10.50.0.77:5556 || true
adb connect 10.50.0.77:5037 || true
adb devices || true
