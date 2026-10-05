. /usr/local/lib/drill/lib.sh
P=hub/packages/com.facility.camerad
CAM=android.permission.CAMERA
g() { adb --mock get "$1" 2>/dev/null; }
if [ "$(g $P/enabled)" = true ]; then ok "com.facility.camerad is still installed"; else bad "com.facility.camerad is missing or disabled (it must be fixed in place, not removed)"; fi
perm=$(g $P/permissions/$CAM/granted)
if [ "$perm" = true ]; then ok "$CAM is granted to com.facility.camerad"; else bad "$CAM is NOT granted to com.facility.camerad"; fi
run=$(g $P/running)
if [ "$perm" = true ] && [ "$run" != true ]; then      # a persistent service comes back within seconds of a bounce
  for i in 1 2 3 4 5 6 7 8; do sleep 0.5; run=$(g $P/running); [ "$run" = true ] && break; done
fi
if [ "$run" = true ]; then ok "com.facility.camerad is running (pid $(g $P/pid))"; else bad "com.facility.camerad is not running ($(g $P/crashes) crashes since boot)"; fi
finish
