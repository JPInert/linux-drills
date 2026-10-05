# mem-hog: live video stutters, app says "network unstable"

WEAK SPOT    "video stutters" is not automatically "network". Rule the
             network out fast, then go per process: top sorted by
             memory, and read RES/RSS (KB), not %MEM.
LOCAL-FIRST  gateway ping is clean, so nothing here needs a network tool.
             Note: in this training box `free -h` shows the HOST's
             memory; on a real edge box it is the first command.

THE SHORT FORMS (this is all you type)
  ip route                     the gateway: the IP after "default via"
  ping -c 3 GATEWAY            rule the link out (the IP from ip route)
  free -h                      used/available (here it reads the host)
  top                          then M (Shift+m): sort by memory
  ps aux | grep motion         the full command line, user and RSS
  systemctl status motion-buffer          Memory: line, Main PID
  cat /etc/motion-buffer.conf  the config says who changed the size
  sudo systemctl stop motion-buffer       stop ONLY the offender
  systemctl is-active analytics videoproc the must-run services

## 1 OBSERVE
SAY: "Network complaint, but the switch and cables are already swapped.
      Ten seconds to rule the network out, then the box."
  $ ip route
    => default via 172.17.0.1 dev eth0   <- the gateway
  $ ping -c 3 172.17.0.1
    => -c 3 = send 3 pings and stop (without it, ping runs until Ctrl+C)
    => 3 received, 0% packet loss, avg 0.1 ms -> not the link
  $ free -h
    => -h = human sizes (G, M) instead of raw bytes
    => real box: how much is used/available; here it reads the host
  $ top
    => press M (Shift+m) to sort by memory, q to quit
    => PID 147  RES 285096  COMMAND motion-+   <- far above the rest
    => next: videoproc 49336, then everything else ~10000 or less
    => press c to see the full command instead of motion-+

## 2 NARROW
SAY: "One process is holding far more than anything else. Which service
      is it, and why is it that big?"
  $ ps aux | grep motion
    => a = all users  u = show the user  x = no terminal too
    => root 147 ... 0.7 290492 285096 ... /opt/motion-buffer/motion-buffer
    => 6th column (RSS) 285096 KB = about 280 MB really in RAM
    => %MEM says 0.7 because it is against the HOST's RAM: trust RSS
  $ systemctl status motion-buffer
    => Main PID: 147 (motion-buffer)   <- same PID as in top
    => Memory: 273.3M
  $ cat /etc/motion-buffer.conf
    => # PREROLL_MB was 32. Raised while chasing missing pre-roll on
       cam-03 (ticket 4471), never put back.
    => PREROLL_MB=270
  $ sudo journalctl -u motion-buffer | head -3
    => -u = only this unit's lines   head -3 = the first 3 (its start)
    => pre-roll buffer allocated: 270 MB ..., eviction disabled
    => it grabs all of it at start and never gives any back

## 3 ACT
SAY: "It is the motion-clip buffer, and clips are allowed to be down.
      Analytics must stay up, so I stop only this one."
  $ sudo systemctl stop motion-buffer
  $ sudo nano /etc/motion-buffer.conf
    => change it back to PREROLL_MB=32, so the next start is not a
       repeat. Ctrl+O, Enter saves, Ctrl+X exits
    => it stays ENABLED: after a reboot it starts with 32 MB, which is
       fine. Leave it that way; don't disable it on your own
  only if the site wants clips off until the vendor call, even across
  a reboot:
      sudo systemctl disable motion-buffer
      (disable = don't start it at boot)

## 4 VERIFY
SAY: "The big resident process is gone, and the services that must run
      are still running."
  $ top
    => M again: videoproc (~49000) is now the biggest; nothing near
       280 MB
  $ systemctl is-active analytics videoproc
    => active
    => active
  $ systemctl is-active motion-buffer
    => inactive

TRAP
  - Restarting the hog re-allocates the same buffer from the same
    config.
  - Restarting or stopping analytics (it "sounds like video") frees
    ~10 MB and takes down the one service that must stay up.
  - `echo 3 > drop_caches` clears page cache, which this is not:
    anonymous memory a process holds is not cache.
  - The largest process is not always the third-party one; the config
    file says who changed the size.

DO IT BETTER
  - Rule the network out fast (gateway ping), then go per process.
  - Read RES/RSS (KB), not %MEM.
  - Stop only the offender: analytics must stay up.
  - Put the config back (PREROLL_MB=32) so the next start is not a
    repeat.
  - ESCALATE / TELL THE CUSTOMER: stopped motion-buffer (280 MB of RAM,
    PREROLL_MB=270 from ticket 4471), set it back to 32; still enabled,
    so it starts small at reboot. Clips are off until it is started.
