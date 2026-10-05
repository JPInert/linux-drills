# data toggle is on but the modem is still powered down by airplane mode
adb shell svc data enable
adb shell "getprop | grep gsm"
