# camera-offline: diagnose, then escalate (know when to stop)

WEAK SPOT    local-first, then STOP. Once the box is proven healthy,
             further poking here is wasted motion.
LOCAL-FIRST  Naming the failed device and the next physical action IS
             the fix.

THE SHORT FORMS (this is all you type)
  cat install-sheet.txt        what the addresses SHOULD be
  ip a                         the box's address (matches the sheet?)
  ip r                         the route: default via the gateway
  ping -c2 10.50.0.254         the first hop is alive
  ping -c2 10.50.1.31          the camera: read WHO answers
  traceroute 10.50.1.31        where it stops: 10.50.0.254 !H
  answer "..."                 name the device and the next physical action

## 1 OBSERVE
SAY: "Before I blame the camera I'll prove the box is healthy: address,
      route, gateway."
  $ cat install-sheet.txt
    => edge-nvr-03  10.50.0.50/24  gateway 10.50.0.254
    => camera1      10.50.1.31
  $ ip a
    => a = address: every network card and its IP
    => eth0 ... inet 10.50.0.50/24     (matches the install sheet)
  $ ip r
    => r = route: where traffic goes
    => default via 10.50.0.254 dev eth0   (anything not local goes to
       the gateway)
  $ ping -c2 10.50.0.254
    => -c2 = send 2 pings and stop (without it: Ctrl-C to stop)
    => 64 bytes from 10.50.0.254 ... 2 received: the first hop is alive

## 2 NARROW
SAY: "Now the camera, and I'll read WHO answers and what it says."
  $ ping -c2 10.50.1.31
    => From 10.50.0.254 icmp_seq=1 Destination Host Unreachable
    => "From 10.50.0.254" = the GATEWAY is answering for the camera,
       saying it can't reach it
  $ traceroute 10.50.1.31
    => one line per hop (router) on the way to the camera
    => the last line is 10.50.0.254 ... !H  (!H = host unreachable)
    => takes ~3 s; if it prints * * * for a while, just wait
SAY: "The gateway is reporting it can't reach the camera. My box, my
      route and the gateway are fine. The camera or its switch port is
      down."
  dig, curl and rebooting the NVR add nothing: they can't fix a dead
  device two hops away

## 3 ACT
SAY: "This can't be fixed from this box. I'm reporting it and asking for
      a hands-on check."
  $ answer "Box healthy (IP, route, gateway ok). Gateway reports camera1 \
      10.50.1.31 unreachable: camera/PoE/switch port down. Do not reboot \
      the NVR. Escalate: on-site tech to check camera power, PoE and \
      cable."
    => \ at a line end = "the command continues on the next line"

## 4 VERIFY
SAY: "I've confirmed the same result twice, from ping and from
      traceroute, and told them what NOT to do."
  $ check

TRAP
  - Rebooting the NVR "to be safe" while the fault is a dead camera.
  - The right answer names the device.
  - The install sheet lists an old router, 10.50.0.1: it is retired.
    Don't chase it; the route says the gateway is 10.50.0.254.

DO IT BETTER
  - Prove the box first: address, route, gateway. Then the camera.
  - Read WHO answers: "From 10.50.0.254 ... Unreachable" is the gateway
    talking, not your box.
  - Once the box is proven healthy, stop poking: name the failed device
    and the next physical action, and say what NOT to do.
