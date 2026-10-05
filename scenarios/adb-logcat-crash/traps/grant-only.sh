# permission fixed, but the crashed service is sitting in ActivityManager's ~1 h restart backoff: nothing restarts it
adb shell pm grant com.facility.camerad android.permission.CAMERA
sleep 3
