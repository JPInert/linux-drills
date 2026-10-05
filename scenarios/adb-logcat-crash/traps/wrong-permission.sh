# grants a different (already granted) permission, then bounces
adb shell pm grant com.facility.camerad android.permission.RECORD_AUDIO
adb shell am force-stop com.facility.camerad
sleep 3
