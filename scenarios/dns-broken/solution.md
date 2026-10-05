# dns-broken: camera1.facility.lan won't resolve

WEAK SPOT    local-first, and dig vs ping. dig asks a server; getent/ping
             use the system resolver.
LOCAL-FIRST  An IP that works while the name fails is never a routing
             problem.

THE SHORT FORMS (this is all you type)
  ping -c1 10.50.1.31                 IP works?
  cat /etc/resolv.conf                which DNS server this box asks
  dig @10.50.0.254 camera1.facility.lan +short
                                      ask the site DNS server directly
  sudo nano /etc/resolv.conf          fix the box's DNS server line
  getent hosts camera1.facility.lan   the system resolver's answer
  curl http://camera1.facility.lan/   the real app path works?

## 1 OBSERVE
SAY: "IP works, name doesn't, so it's resolution. Which resolver is this
      box using?"
  $ ping -c1 10.50.1.31
    => -c1 = send 1 ping and stop (without it ping runs until Ctrl-C)
    => 64 bytes from 10.50.1.31: the camera is reachable by IP
  $ ping -c1 camera1.facility.lan
    => Temporary failure in name resolution
  $ cat /etc/resolv.conf
    => nameserver 10.50.0.99      <- not the site DNS
  $ cat ~/install-sheet.txt
    => DNS 10.50.0.254

## 2 NARROW
SAY: "The install sheet says DNS is 10.50.0.254. Let me ask that server
      directly."
  $ dig @10.50.0.254 camera1.facility.lan +short
    => @10.50.0.254 = ask THIS server, not the one in resolv.conf
    => +short = print only the answer, not the full report
    => 10.50.1.31: the site DNS server is fine
  $ dig @10.50.0.99 camera1.facility.lan
    => waits ~15 s, then: no servers could be reached
    => the server this box is using does not exist

## 3 ACT
SAY: "The server is healthy; this box points at the wrong one. Fixing
      resolv.conf."
  $ sudo nano /etc/resolv.conf
    => change  nameserver 10.50.0.99  to  nameserver 10.50.0.254
    => keep the  search facility.lan  line
    => Ctrl-O then Enter saves, Ctrl-X quits
    => here resolv.conf is a Docker bind mount, so sed -i fails
       ("Device or resource busy"): nano writes in place, sed swaps
       in a new file
    => on a real server it may be managed by systemd-resolved /
       NetworkManager, in which case fix it THERE or the edit is
       overwritten

## 4 VERIFY
SAY: "Resolve it three ways: dig, the system resolver, and the real
      application."
  $ dig camera1.facility.lan +short
    => no @ this time: uses the server in resolv.conf
    => 10.50.1.31
  $ getent hosts camera1.facility.lan
    => asks the way programs do (resolv.conf AND /etc/hosts)
    => 10.50.1.31      camera1.facility.lan
  $ curl http://camera1.facility.lan/
    => camera1 - RTSP relay OK - stream 1080p30
  $ check

TRAP
  - an /etc/hosts entry makes THIS box work and hides a broken resolver
    that every other host also uses.
  - Pointing at 8.8.8.8 does not know the internal .lan zone.
  - `sudo sed -i` on resolv.conf fails in this container: it is a Docker
    mount. Use nano, which edits the file in place.

DO IT BETTER
  - IP works, name fails: it's resolution, never routing.
  - Ask the site DNS server directly (dig @10.50.0.254) before touching
    the box, so you know which side is broken.
  - Fix resolv.conf where it is managed, or the edit is overwritten.
  - Verify three ways: dig, the system resolver (getent), and the real
    application (curl).
