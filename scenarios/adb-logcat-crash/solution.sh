set -e
adb shell pm grant com.facility.camerad android.permission.CAMERA   # give the runtime permission back
adb shell am force-stop com.facility.camerad                        # bounce it: a persistent app restarts at once
sleep 3
adb shell ps -A | grep -q com.facility.camerad                      # it is running again
