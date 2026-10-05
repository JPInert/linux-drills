# adb-logcat-crash: hub camera service keeps dying after the OS update

WEAK SPOT    The device has its OWN log and its OWN package manager.
             `adb logcat`, `pm`, `dumpsys package` are its journalctl + ls -l.
LOCAL-FIRST  "Uploads stopped" sounds like network, but the service on the
             hub is DEAD. Nothing to ping.

THE SHORT FORMS (this is all you type)
  adb shell pm list packages camera      find the app's full name
  adb shell ps -A | grep camerad         is it running? (no quotes needed:
                                         the grep runs on your laptop)
  adb logcat -d | grep -i fatal          THE habit: dump the log, grep a word
  adb logcat -d -b crash | head          just the crash log
  adb shell dumpsys package com.facility.camerad | grep -i camera
                                         what it was granted
  adb shell pm grant com.facility.camerad android.permission.CAMERA
                                         give it back
  adb shell am force-stop com.facility.camerad
                                         bounce it (a persistent app restarts)
  Tip: `adb shell` alone opens a prompt on the hub: type `ps -A | grep x`
  there without the `adb shell` prefix.

## 1 OBSERVE
SAY: "Uploads stopped after an OS update. Is the camera service even
      running on the hub?"
  $ adb devices
    => a3f7c19e   device       (first call prints "* daemon" lines: normal)
  $ adb shell pm list packages camera
    => pm = the hub's package manager; this lists apps with "camera" in
       the name
    => package:com.facility.camerad
  $ adb shell ps -A | grep camerad
    => ps -A = every process on the hub (-A = all)
    => prints nothing: it is not running
  $ adb logcat -d | grep -i fatal
    => logcat = the hub's log. -d = print what is there and stop
       (without it, it follows forever: Ctrl-C to quit)
    => grep -i = ignore upper/lower case
    => 7 lines of "E AndroidRuntime: FATAL EXCEPTION: main", the gaps
       between them growing (13:53, 13:53, 13:53, 13:54, 13:58, 14:16)

## 2 NARROW
SAY: "It crashes on start. What is the exception, and which permission
      does it name?"
  $ adb logcat -d -b crash | head
    => -b crash = only the crash log; head = the first 10 lines
    => Process: com.facility.camerad
    => java.lang.SecurityException: Permission Denial: opening camera 0
       ... requires android.permission.CAMERA
  $ adb logcat -d | grep -i restart | tail -2
    => tail -2 = only the last 2 lines
    => Scheduling restart of crashed service ... in 3600000ms
    => (3600000 ms = 1 hour: it is parked in restart backoff)
  $ adb shell dumpsys package com.facility.camerad | grep -i camera
    => dumpsys package = everything the hub knows about one app
    => android.permission.CAMERA: granted=false      <- the update reset it
  $ adb logcat -d -b system | grep -i permission
    => -b system = the OS's own log
    => CAMERA reset by platform upgrade, needs re-grant   <- the why

## 3 ACT
SAY: "Give it the permission back, then bounce it. It is parked in
      restart backoff, so the grant alone will not wake it."
  $ adb shell pm grant com.facility.camerad android.permission.CAMERA
    => prints nothing when it works
  $ adb shell am force-stop com.facility.camerad
    => am = the hub's app manager. A persistent app like this one is
       started again straight away

## 4 VERIFY
SAY: "Confirm it is running and the log shows it came up, not crashed."
  $ adb shell ps -A | grep camerad
    => u0a87   4756 ...  com.facility.camerad      (a PID: it is up)
  $ adb logcat -d | grep -i camera | tail -3
    => camera 0 opened (1920x1080@30), stream ... up
    => service ready, snapshots -> NOC uploader (cam0)
  $ adb logcat -d | grep -ci fatal
    => -c = count the matching lines instead of printing them
    => still 7: the count has stopped growing

TRAP
  - `am force-stop` alone: it crashes again (permission still revoked).
  - `pm grant` alone is right, but it stays dead for the ~1 h backoff.
  - `pm clear` wipes the hand-provisioned config and does NOT restore
    permissions.
  - Reboot: same crash at boot.

DO IT BETTER
  - One habit for every log question: adb logcat -d | grep -i WORD.
    (Level filters like '*:E' need quotes: bash expands the *.)
  - Order: evidence (log) -> state (dumpsys) -> change (pm grant)
    -> restart -> prove.
  - Prove it from the log ("service ready"), not because a command
    printed nothing.
