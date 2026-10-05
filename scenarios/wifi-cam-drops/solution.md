# wifi-cam-drops: camera7 keeps dropping, should we replace it?

WEAK SPOT    "it drops, so it's broken" is a guess. Compare the bad one
             with a good one, field by field, and let the camera's own
             status say whether it is the camera or its link.
LOCAL-FIRST  All the evidence is already on this box: the NVR's log and
             the status it polls from every camera. Nothing to fix here:
             prove it, then escalate with the numbers.

THE SHORT FORMS (this is all you type)
  systemctl --failed           the sweep: is anything on the box dead?
  cat /etc/nvr/cameras.conf    which cameras are WiFi, which wired
  grep OFFLINE /var/log/nvr/nvr.log | grep -o 'cam[0-9]*' | sort | uniq -c
                               drops per camera
  grep cam07 /var/log/nvr/nvr.log | grep OFFLINE | cut -c1-13 | sort \
      | uniq -c                drops per hour: when does it happen?
  cat /var/lib/nvr/cameras/cam07.json    the camera's own status
  grep rssi /var/lib/nvr/cameras/*.json  signal of every WiFi camera
  grep uptime /var/lib/nvr/cameras/*.json    did any camera reboot?
  answer "..."                 cause + number + who does what

## 1 OBSERVE
SAY: "Before I blame the camera I'll see how it is connected, and how
      often it really drops compared with the others."
  $ systemctl --failed
    => the playbook sweep first: anything dead on the box itself?
    => fwupd-refresh.service  failed: a firmware-metadata download that
       can't reach the internet. Nothing to do with cameras: note it,
       move on
  $ nvidia-smi
    => analytics.py holds the GPU: the box is healthy
  $ cat /etc/nvr/cameras.conf
    => cam01-05 wired; cam06 Courtyard, cam07 Dining Room, cam08
       Library are WiFi
  $ grep OFFLINE /var/log/nvr/nvr.log | grep -o 'cam[0-9]*' | sort \
      | uniq -c
    => grep -o = print only the part that matched (cam07), not the line
    => sort puts the same names together; uniq -c counts each run
    => 1 cam03   45 cam07   (your numbers will differ)
    => the other two WiFi cameras never drop: WiFi itself is not broken
    => the single cam03 blip days ago is noise, like the old "disk busy"
       ERROR: old, one-off, not this ticket
  $ grep 'stream cam07' /var/log/nvr/nvr.log | tail -3
    => the quotes keep "stream cam07" as ONE search (it has a space)
    => no frames for 10 s, marking OFFLINE / RTSP connect ... timed
       out, retrying / reconnected after 64 s: lost, then back

## 2 NARROW
SAY: "Now WHEN it drops, and what the camera itself reports."
  $ grep cam07 /var/log/nvr/nvr.log | grep OFFLINE | cut -c1-13 | sort \
      | uniq -c
    => cut -c1-13 = keep characters 1-13: the date and the hour
    => 3 ... 07   3 ... 12   5 ... 18: breakfast, lunch, dinner. The
       dining room is full and the microwaves run (2.4 GHz, like WiFi)
  $ cat /var/lib/nvr/cameras/cam07.json
    => "uptime_s": 405042      = 4.7 days (divide by 86400): the camera
       has NOT rebooted once through 45 drops. It is alive; its link
       is what goes
    => "band": "2.4GHz", "channel": 6
    => "rssi_dbm": -83         signal strength: -50 strong, -70 fair,
                               -80 and below weak
    => "tx_rate_mbps": 6.5     the slowest WiFi speed: a bad link
    => "tx_retries_pct": 44    almost half of what it sends is re-sent
    => "neighbor_aps_same_channel": 13   a crowded channel
    => "firmware_update_available": "2.1.4": cam03 has the same notice
       and is wired and fine. Not the cause
  $ grep rssi /var/lib/nvr/cameras/*.json
    => grep in many files prints file:line
    => cam06 -54   cam07 -83   cam08 -49: same model, same network,
       only camera7 is far from the access point
SAY: "The camera is fine. Its WiFi signal is weak and noisy at -83 dBm on
      a crowded channel, and it drops when the dining room is busy."

## 3 ACT
SAY: "Nothing on this box can move an access point. I'll report it with
      the numbers so their IT can act, and say not to buy a camera."
  $ answer "camera7 is not faulty (uptime 4.7 days, never rebooted). \
      Weak WiFi: RSSI -83 dBm, 44% retries, 6.5 Mbps, channel 6 with \
      13 neighbour APs; the other WiFi cams are -49/-54. Don't replace \
      the camera or reboot the NVR. Escalate to the customer's IT: add \
      or move an AP near the dining room, change channel, or wire it \
      with PoE."
    => use YOUR numbers from cam07.json

## 4 VERIFY
SAY: "Same picture from three angles: only cam07 drops, only cam07 has a
      weak signal, and the camera never restarted."
  $ grep uptime /var/lib/nvr/cameras/*.json
    => every camera is up for days: none of them crashed
  $ check

TRAP
  - Replacing the camera: a new one in the same spot gets the same -83.
  - Rebooting the NVR: the NVR only reports the loss; it never caused it.
  - The firmware notice: cam03 has it too and never drops.
  - "WiFi problem" with no number: IT needs the RSSI, the channel and
    the room to act on it.

DO IT BETTER
  - Compare the bad one with a good one of the same kind, field by
    field (grep one key across every file).
  - Uptime tells you if a device crashed or only lost its link.
  - ESCALATE / TELL THE CUSTOMER: "camera7 RSSI -83 dBm, 44% retries,
    channel 6 crowded, drops at meal times. Add or move an AP near the
    dining room, change channel, or run a PoE cable. Don't replace it."
