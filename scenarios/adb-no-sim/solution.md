# adb-no-sim: hub's cellular backup link is dead, SIM "not ready"

WEAK SPOT    rfkill / ip link manage the radios of the machine you type on.
             The hub's modem belongs to the hub's Android: drive it with adb.
LOCAL-FIRST  "Radios seem off" is a device setting. Don't ping or reseat
             anything yet.

THE SHORT FORMS (this is all you type)
  adb shell getprop | grep gsm           SIM + network state (want LOADED, LTE)
  adb shell ip -br a                     one line per interface: rmnet_data0
                                         is the cellular one (DOWN = no link)
  adb shell settings list global | grep airplane       switch 1 (want 0)
  adb shell settings list global | grep mobile_data    switch 2 (want 1)
  adb logcat -d -b radio | tail          the modem's own log
  adb shell dumpsys telephony.registry | grep mDataConnectionState
                                         0 = no data, 2 = connected
  adb shell cmd connectivity airplane-mode disable    airplane OFF
  adb shell svc data enable                           mobile data ON
  Tip: `adb shell` alone opens a prompt on the hub: type `getprop | grep gsm`
  there without the `adb shell` prefix.

## 1 OBSERVE
SAY: "The backup link is dead. What does the hub say about its SIM and
      network?"
  $ adb devices
    => a3f7c19e   device
  $ adb shell getprop | grep gsm
    => getprop = every hub setting; grep keeps the lines with "gsm"
    => [gsm.sim.state]: [NOT_READY]   [gsm.network.type]: [Unknown]
  $ adb shell ip -br a
    => ip a = list interfaces; -br = brief, one line each
    => rmnet_data0   DOWN            (no address)
  $ adb shell ping -c2 8.8.8.8
    => -c2 = send two pings, then stop
    => 100% packet loss: expected (WAN is pulled), but it does not say WHY

## 2 NARROW
SAY: "NOT_READY, not ABSENT: the card is seated, the modem is not
      running. Why?"
  $ adb shell settings list global | grep airplane
    => settings list global = every system-wide switch on the hub
    => airplane_mode_on=1               <- the cause
  $ adb shell settings list global | grep mobile_data
    => mobile_data=0                    <- a second, separate problem
  $ adb logcat -d -b radio | tail
    => logcat = the hub's log. -d = print what is there and stop
       (without it, it follows forever: Ctrl-C to quit)
    => -b radio = the modem's own log (it is not in the normal one)
    => pollStateDone: OUT_OF_SERVICE (radio off)
    => Card state PRESENT, app state NOT_READY (radio off)
  $ adb shell dumpsys telephony.registry | grep mDataConnectionState
    => dumpsys = the phone service's live state
    => mDataConnectionState=0

## 3 ACT
SAY: "Airplane mode off the supported way, then mobile data on: two
      switches."
  $ adb shell cmd connectivity airplane-mode disable
    => prints nothing when it works
  $ adb shell svc data enable
    => prints nothing when it works
  Older way:  adb shell settings put global airplane_mode_on 0
              adb shell am broadcast -a android.intent.action.AIRPLANE_MODE
              (`put` alone changes the setting; nothing tells the radio)

## 4 VERIFY
SAY: "I judge by what the modem reports, not by the last command I typed."
  $ adb shell getprop | grep gsm
    => [gsm.sim.state]: [LOADED]   [gsm.network.type]: [LTE]
    => (airplane off alone already gets you this far, but
       rmnet_data0 stays DOWN until mobile data is on too)
  $ adb shell ip -br a
    => rmnet_data0   UNKNOWN   100.72.18.33/30     (it has an address now)
  $ adb shell ping -c2 8.8.8.8
    => 2 received: the WAN is unplugged, so this only works over LTE now
  $ adb logcat -d -b radio | tail -4
    => -4 = just the last 4 lines
    => "Registered on Coastal Wireless (00101) LTE"
    => "Data connected: apn=internet, iface=rmnet_data0"

TRAP
  - `rfkill unblock all` on the laptop does nothing to the hub.
  - `settings put ... airplane_mode_on 0` alone leaves the radio off.
  - Airplane fixed but mobile data off = no link.
    Data on but airplane on = still no service.
  - A reboot keeps both persistent settings.

DO IT BETTER
  - Two switches, two checks: airplane_mode_on AND mobile_data.
  - Read gsm.sim.state literally: NOT_READY (radio off) is not ABSENT
    (no card).
  - Verify the effect (LOADED + LTE, rmnet_data0 has an address, ping),
    not the setting you changed.
