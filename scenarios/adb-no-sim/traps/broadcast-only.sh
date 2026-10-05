# the broadcast reads the SETTING, which still says airplane mode is on: nothing changes
adb shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false
adb shell svc data enable
