# flips the setting but nothing tells the radio to follow (no broadcast): the modem stays off
adb shell settings put global airplane_mode_on 0
adb shell svc data enable
adb shell settings get global airplane_mode_on
