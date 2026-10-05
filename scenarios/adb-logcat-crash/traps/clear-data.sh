# wipes the hand-provisioned config and bounces; runtime permissions are not restored by a data clear
adb shell pm clear com.facility.camerad
adb shell am force-stop com.facility.camerad
sleep 3
