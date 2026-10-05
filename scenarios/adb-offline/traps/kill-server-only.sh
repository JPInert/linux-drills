# a clean server, but the network device is never re-added (adb does not auto-discover TCP devices)
adb kill-server
adb start-server
adb devices || true
