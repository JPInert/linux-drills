# chain-gpu-thermal: alerts late every afternoon, the GPU is capped

WEAK SPOT    "Only in the afternoon" is a clue about HEAT, not traffic.
             nvidia-smi shows temperature, fan, power cap and WHY the
             clocks are held back; the journal shows who set it.
LOCAL-FIRST  Local. Nothing about the network changes; the card slows.

THE SHORT FORMS (this is all you type)
  systemctl --failed               anything dead? (sweep)
  tail -4 /var/log/analytics/detect.log     what the detector says
  grep WARN /var/log/analytics/detect.log | cut -c12-13 | sort | uniq -c
  nvidia-smi                       Fan, Temp, Pwr:Usage/Cap at a glance
  nvidia-smi -q -d PERFORMANCE,POWER    why the clocks are held back
  sudo journalctl -b | grep -i "power limit"   who set the cap
  systemctl cat gpu-quiet          the unit that did it
  cat /etc/default/gpu-quiet       its settings, and WHY it exists
  sudo systemctl disable gpu-quiet stop it running at boot
  sudo nvidia-smi -pl 70           vendor power limit back, now
  sudo gpu-fan --auto              automatic fan curve back, now

## 1 OBSERVE
SAY: "Late only in the afternoon. Before I blame the WiFi: the sweep,
      then what the detector itself reports."
  $ systemctl --failed
    => fwupd-refresh.service: firmware metadata, no internet. Unrelated.
  $ tail -4 /var/log/analytics/detect.log
    => fps=14.2 device=cuda:0 ... sm_clock=1050MHz
    => WARN detect: inference behind real time (14.2 fps < 24):
       alert latency 3.2s over SLO 2.0s
    => it is ON the GPU, but the GPU runs slowly (1050 MHz)
  $ grep WARN /var/log/analytics/detect.log | cut -c12-13 | sort | uniq -c
    => cut -c12-13 = characters 12-13 of each line: the hour
    => sort | uniq -c = count how many lines per hour
    => only hours 13 to 18 (and now): every afternoon, never mornings
  $ sudo grep -i nvrm /var/log/kern.log.1
    => NVRM: Xid 13 ... 40 days ago, one burst, never again. An old
       driver hiccup, not today's slowness. Red herring.

## 2 NARROW
SAY: "The detector waits on the GPU. Ask the card how it is doing."
  $ nvidia-smi
    => 25%   87C   P2   36W /  40W
    => fan 25%, 87 C, and a 40 W cap on a card whose default is 70 W
  $ nvidia-smi -q -d PERFORMANCE,POWER
    => -q = the full query report. -d = only these sections
    => Clocks Event Reasons: SW Power Cap : Active
                             SW Thermal Slowdown : Active
    => Current Power Limit 40.00 W, Default Power Limit 70.00 W
    => two brakes at once: the power cap and the heat
  $ gpu-fan
    => GPU 0 fan policy: manual, capped at 25%
SAY: "Somebody capped this card. The journal says who."
  $ sudo journalctl -b | grep -i "power limit"
    => -b = this boot only
    => gpu-quiet[240]: Power limit for GPU ... was set to 40.00 W
       from 70.00 W.
  $ systemctl cat gpu-quiet
    => a oneshot at boot: EnvironmentFile=/etc/default/gpu-quiet,
       ExecStart=/usr/local/sbin/gpu-quiet
  $ cat /etc/default/gpu-quiet
    => "server closet next to the attendants' break room ... ticket
       HR-4471 (fan noise during night shift)". POWER_LIMIT=40,
       FAN_MAX=25
SAY: "Quiet mode for a noise complaint. Fine when the closet is cool;
      in the afternoon the card hits 87 C and throttles."

## 3 ACT
SAY: "The noise complaint is real, but throttling the vehicle counter is
      the wrong fix. I stop it at boot, keep the file as the record,
      undo it now, and hand the noise back to the site."
  $ sudo systemctl disable gpu-quiet
    => disable = don't start at boot. It does NOT undo what it already
       did to the card
  $ sudo nvidia-smi -pl 70
    => -pl = power limit in watts. "set to 70.00 W from 40.00 W"
  $ sudo gpu-fan --auto
    => the driver's automatic fan curve again
  $ answer "gpu-quiet (noise ticket HR-4471) capped the GPU at 40 W, \
      fan 25%; afternoon heat made it throttle and alerts ran late. \
      Restored 70 W + auto fan, disabled gpu-quiet. Noise: facilities \
      fix (closet door/insulation, move the box), not GPU caps."

## 4 VERIFY
SAY: "Proving the card runs free and the detector keeps up."
  $ nvidia-smi
    => 55%   66C   P2   52W /  70W
  $ nvidia-smi -q -d PERFORMANCE
    => every Clocks Event Reason: Not Active
  $ tail -2 /var/log/analytics/detect.log
    => fps=24.0 device=cuda:0 ... sm_clock=1770MHz
  $ systemctl is-enabled gpu-quiet
    => disabled: it won't come back at the next boot
  $ check

TRAP
  - Only -pl 70: the fan is still capped, it thermal-throttles.
  - Only the fan: the 40 W cap still holds the clock down.
  - Fixing it live but leaving gpu-quiet enabled: next reboot, same.
  - systemctl stop / disable alone: a oneshot's changes stay on the card.
  - rm the unit and its files: works, and erases why it existed.
  - DEVICE=cpu, restarting analytics, chasing the old Xid or the WiFi.

DO IT BETTER
  - "Only at certain times" = look for what changes then: heat, load,
    a timer. nvidia-smi -q -d PERFORMANCE names the brake.
  - A changed setting nobody remembers: journalctl -b | grep it.
  - ESCALATE / TELL THE SITE: "The quiet mode from HR-4471 throttled
    the vehicle-counting GPU and delayed alerts; it is off. Please solve
    the closet noise with facilities (door seal, acoustic panel, or
    moving the box), not by limiting the GPU."
