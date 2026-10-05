# The hub is plugged into this laptop over USB. The overnight OS update reset the runtime CAMERA permission of
# com.facility.camerad, so the (persistent) camera service crash-loops on start; ActivityManager's restart backoff has
# grown to ~1 h, so the service is simply dead right now. The mock adb writes the crash history itself (it back-fills the
# backoff timeline from next_restart); only the state and some background log noise are set here.
install -d -m 0700 /var/lib/mock-adb
now=$(date +%s)
cat > /var/lib/mock-adb/state.json <<JSON
{
  "hub": {
    "boot_epoch": $((now - 1620)),
    "packages": {
      "com.facility.camerad": {
        "running": false, "pid": 0, "restart_delay": 1, "next_restart": $((now - 1560)),
        "permissions": {"android.permission.CAMERA": {"granted": false, "flags": ""}}
      }
    }
  }
}
JSON
chmod 0600 /var/lib/mock-adb/state.json
adb --mock noise main 40 1500
adb --mock noise system 6 1500
adb --mock log system 1690 1188 1230 I PackageManager "Reconciling permissions after OS upgrade 2026.08.2 -> 2026.09.1"
adb --mock log system 1688 1188 1230 W PermissionMgr "com.facility.camerad: runtime permission android.permission.CAMERA reset by platform upgrade, needs re-grant"
adb --mock tick
