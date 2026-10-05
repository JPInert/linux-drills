# poe-budget: cameras 5-8 die every evening at 7

WEAK SPOT    a time pattern is a clue: ask "what changes at that time?"
             Find the one device the failing cameras share, read ITS log,
             throw out what happens all day, and line two logs up by the
             minute.
LOCAL-FIRST  The switches send their logs to this box, so the proof is
             here. The fix is on the customer's switch: escalate it.

THE SHORT FORMS (this is all you type)
  systemctl --failed           the sweep: is anything on the box dead?
  cat /etc/nvr/cameras.conf    which switch and port each camera is on
  ls -l /var/log/remote        the logs the switches send to this box
  grep -c CDP /var/log/remote/switch-2f.log      count the noise
  grep -i power /var/log/remote/switch-2f.log | head
                               the power lines, first ones first
  grep DENY /var/log/remote/switch-2f.log | grep -o 'Gi1/0/[0-9]*' \
      | sort | uniq -c         which ports lose power
  grep DENY /var/log/remote/switch-2f.log | cut -c1-9 | sort | uniq -c
                               at which hours
  grep '2026-09-23 18:5' /var/log/nvr/nvr.log
                               the NVR at the same minutes
  grep -ci power /var/log/remote/switch-1f.log   the other switch: 0
  answer "..."                 cause + trigger + who does what

## 1 OBSERVE
SAY: "Four cameras, same hours, every day. First: what do they share?"
  $ systemctl --failed
    => the playbook sweep first: anything dead on the box itself?
    => fwupd-refresh.service  failed: a firmware-metadata download that
       can't reach the internet. Nothing to do with cameras: note it,
       move on
  $ nvidia-smi
    => analytics.py holds the GPU: the box is healthy
  $ cat /etc/nvr/cameras.conf
    => cam01-04 on sw-1f, cam05-08 on sw-2f ports Gi1/0/5 to Gi1/0/8
    => the four failing cameras are exactly the ones on sw-2f
  $ ls -l /var/log/remote
    => switch-1f.log  switch-2f.log: each switch sends its log here
  $ head -3 /var/log/remote/switch-2f.log
    => %CDP-4-NATIVE_VLAN_MISMATCH ... GigabitEthernet1/0/10: scary, and
       the first thing you see
  $ grep -c CDP /var/log/remote/switch-2f.log
    => -c = count the matching lines instead of printing them
    => 147: it repeats all day and all night, on the uplink port, not a
       camera port. A thing that never changes can't explain 7 pm.
       Note it for IT, then ignore it

## 2 NARROW
SAY: "The cameras are powered by this switch over the cable, PoE. I'll
      search its log for power."
  $ grep -i power /var/log/remote/switch-2f.log | head
    => -i = ignore case (matches Power, POWER, power)
    => Sep 23 18:57:24 ... %ILPOWER-4-BUDGET_EXCEEDED: PoE power budget
       exceeded: requested 75.3 W, available 67.0 W
    => ... ILPOWER_POWER_DENY: Interface Gi1/0/8: inline power denied.
       Reason: insufficient power
    => ... IEEE_DISCONNECT: Interface Gi1/0/8: PD removed (PD = the
       powered device: the camera)
  $ grep DENY /var/log/remote/switch-2f.log | grep -o 'Gi1/0/[0-9]*' \
      | sort | uniq -c
    => grep -o = print only the matched part: the port name
    => sort groups the same ports; uniq -c counts each group
    => 59 Gi1/0/5  79 Gi1/0/6  65 Gi1/0/7  56 Gi1/0/8: only cams 5-8
  $ grep DENY /var/log/remote/switch-2f.log | cut -c1-9 | sort | uniq -c
    => cut -c1-9 = keep characters 1 to 9: "Sep 23 19" = day + hour
    => rows only for hours 18 to 06, none in daytime: every night, the
       switch keeps re-powering the cameras and cutting them off again
SAY: "Why at 7? I take the first BUDGET line's time and read the NVR log
      at the same minutes. Its dates look different: 2026-09-23 18:57."
  $ grep '2026-09-23 18:5' /var/log/nvr/nvr.log
    => use YOUR date and the first minute from the head output above
    => 18:53-18:56 every camera: day/night switch -> NIGHT (IR
       illuminator on)
    => 18:57:33 onwards: stream cam08, 07, 06, 05 ... marking OFFLINE
    => dark -> the infrared lights turn on -> each camera draws more
       power -> the switch is over its 67 W -> it cuts ports off
  $ grep -ci power /var/log/remote/switch-1f.log
    => -c with -i: count, ignoring case. 0: cams 1-4 turn IR on too,
       but their switch has power to spare
SAY: "In the morning it is light, the cameras boot without IR, and they
      fit the budget again. It is the switch's PoE budget, not the NVR."

## 3 ACT
SAY: "I can't add watts from here. I'll hand IT the numbers."
  $ answer "Not the NVR. sw-2f runs out of PoE budget (requested ~75 W, \
      available 67 W) when cams 5-8 turn their IR on at dusk; it denies \
      power to Gi1/0/5-8 all night. Escalate to their network team: \
      raise the PoE budget (bigger PSU / PoE+ switch) or move cameras \
      to another switch or injectors. Don't turn IR off."
    => \ at a line end = "the command continues on the next line"

## 4 VERIFY
SAY: "Same story from both logs: power cut on only these four ports,
      only at night, a minute after their IR came on."
  $ check

TRAP
  - Rebooting the NVR: it only reports the loss; the switch cut power.
  - Replacing the cameras: new ones draw the same power with IR on.
  - The native VLAN mismatch: scary, constant, on the uplink port. It
    does not change at 7 pm.
  - Turning IR off: the cameras stay up and see nothing in the dark, in
    a building that watches for falls at night.

DO IT BETTER
  - A clock pattern means "what changes then?": find it in a log.
  - Count with sort | uniq -c per port and per hour before reading
    lines one by one.
  - Line two logs up by the minute, even when their date formats differ.
  - ESCALATE / TELL THE CUSTOMER: "sw-2f PoE budget 67 W, needs ~75 W
    once IR is on at dusk; ports Gi1/0/5-8 denied power all night. Raise
    the budget or move cameras. Also: native VLAN mismatch on Gi1/0/10."
