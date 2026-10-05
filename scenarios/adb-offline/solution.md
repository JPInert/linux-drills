# adb-offline: new hub won't show up for provisioning

WEAK SPOT    adb = a client PLUS a background server. `adb devices` prints the
             SERVER's table, not the network. "offline" = a stale entry.
LOCAL-FIRST  ping/nc only prove the hub is alive. They can't tell you adb is
             attached. A healthy ping + an empty `adb devices` IS this ticket.

THE SHORT FORMS (this is all you type)
  adb devices                 what adb thinks. Read the STATE column
  adb kill-server             wipe the server's table (next adb call restarts)
  adb connect 10.50.0.77      add a network device (port defaults to 5555)
  adb shell getprop ro.product.model     prove you can talk to it
  One device attached = no -s needed. Two = adb -s SERIAL shell ...

## 1 OBSERVE
SAY: "The tool sees nothing. What does adb itself say about the hub?"
  $ adb devices
    => 10.50.0.77:5555   offline
    => column 1 = the device's name (here IP:port), column 2 = STATE
  $ adb shell getprop ro.product.model
    => adb shell CMD = run CMD on the hub; getprop = read a hub setting
    => error: device offline

## 2 NARROW
SAY: "adb has the hub but calls it offline. Is the hub alive? Will a
      plain connect fix it?"
  $ ping -c1 10.50.0.77
    => -c1 = send one ping and stop (without it ping runs until Ctrl-C)
    => 1 received: the network is fine
  $ nc -zv 10.50.0.77 5555
    => nc = netcat, pokes a port. -z = just test it, send nothing,
       -v = print what happened
    => Connection to 10.50.0.77 5555 port succeeded!
    => something (the hub's adbd) is listening on 5555
  $ adb connect 10.50.0.77
    => already connected to 10.50.0.77:5555
  $ adb devices
    => ...and it is STILL offline: the stale entry wins

## 3 ACT
SAY: "The server's table is stale. I wipe the server and add the hub
      again by hand."
  $ adb kill-server
    => stops adb's background server and throws its table away
  $ adb connect 10.50.0.77
    => * daemon not running; starting now ...    (normal noise)
    => connected to 10.50.0.77:5555
  Also valid:  adb disconnect 10.50.0.77 ; adb connect 10.50.0.77
               adb reconnect offline

## 4 VERIFY
SAY: "The state column must say `device`. Then I prove I can talk to it."
  $ adb devices
    => 10.50.0.77:5555   device
  $ adb shell getprop ro.product.model
    => Facility Hub QCS6490

TRAP
  - `adb connect` alone on an offline entry only prints "already connected".
  - Wrong port (:5556, or 5037 = adb's own server port): "Connection refused".
  - ping proves the network, never adb.

DO IT BETTER
  - Read the STATE column, not just whether the hub is listed.
  - Verify with a command that runs ON the device (getprop), not by the
    last command you typed.
  - Two devices attached and adb says "more than one device/emulator"?
    Add -s SERIAL (column 1 of `adb devices`), -s = pick this one.
