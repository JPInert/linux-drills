# wrong-gateway: camera VLAN unreachable

WEAK SPOT    local-first. Everything you need is on THIS box: address,
             route, then the first hop (and WHICH device is answering as
             hop 1).
LOCAL-FIRST  Do not start with the camera or the switch. `ip a` and `ip r`
             before `ping`.

THE SHORT FORMS (this is all you type)
  ip a                         my address (the inet line under eth0)
  ip r                         my routes (look at "default via")
  cat ~/install-sheet.txt      what they SHOULD be
  ping -c 3 10.50.0.254        is the right gateway alive?
  traceroute 10.50.1.31        WHICH device answers as hop 1
  sudo ip route replace default via 10.50.0.254     swap the default
  curl http://10.50.1.31/      the application, not just ping

## 1 OBSERVE
SAY: "Camera offline. First the box: do I have an address, a route, and
      does the first hop answer?"
  $ ip a
    => a = address: every network card and its IP
    => eth0 ... inet 10.50.0.50/24
    => fine, matches the install sheet (lo is the box talking to itself)
  $ ip r
    => r = route: where the box sends traffic
    => default via 10.50.0.1 dev eth0        <- suspicious
    => 10.50.0.0/24 dev eth0 ... src 10.50.0.50
    => default = "anything not on my own subnet goes to this gateway";
       the camera is on 10.50.1.x, so it goes via 10.50.0.1
  $ cat ~/install-sheet.txt
    => edge-nvr-03  10.50.0.50/24  gateway 10.50.0.254
    => retired: old site router 10.50.0.1 (it no longer routes anything)

## 2 NARROW
SAY: "Address is right, route points at the old router. Is the real
      gateway alive, and where does my traffic actually go?"
  $ ping -c 3 10.50.0.254
    => -c 3 = send 3 pings then stop (without it ping runs until Ctrl+C)
    => 3 packets transmitted, 3 received, 0% packet loss
    => the real gateway is alive
  $ ping -c 3 10.50.1.31
    => 3 packets transmitted, 0 received, 100% packet loss
  $ traceroute 10.50.1.31
    => lists each router (hop) on the way to the camera
    => 1  10.50.0.1 (10.50.0.1)  0.137 ms ...
    => 2  * * *
    => 3  * * *     (* = no answer; Ctrl+C to stop, it tries 30 hops)
    => hop 1 is the RETIRED router, and the path dies right after it

## 3 ACT
SAY: "I'll replace the default route so it uses the gateway on the
      install sheet."
  $ sudo ip route replace default via 10.50.0.254
    => replace = swap the existing default for this one (no output = ok)
  Then persist it in the network config too, or it comes back at
  reboot; tell the customer

## 4 VERIFY
SAY: "Confirm the path and the application, not just ping."
  $ ip r
    => default via 10.50.0.254 dev eth0      (one default, the right one)
  $ traceroute 10.50.1.31
    => 1  10.50.0.254 (10.50.0.254)  0.516 ms ...
    => 2  10.50.1.31 (10.50.1.31)  0.393 ms ...
  $ curl http://10.50.1.31/
    => curl fetches a web page and prints it
    => camera1 - RTSP relay OK - stream 1080p30
  $ check

TRAP
  - `ip route add default ...` while the old default exists gives TWO
    defaults (the lower metric wins). Use `replace`.
  - Adding a static route for the /24 works, but leaves the bad default
    behind.

DO IT BETTER
  - `ip a` and `ip r` before `ping`: the box first, then the first hop.
  - Check WHICH device answers as hop 1, not just that one answers.
  - Confirm the application (curl), not just ping.
  - Persist the route, or it comes back at reboot.
