# wrong-ip: 403 from the camera, box on the wrong address

WEAK SPOT    local-first. ping works, the network is fine. The fault is the
             box's OWN identity.
LOCAL-FIRST  "It says 403" = the far end answered. That is not a routing
             problem.

THE SHORT FORMS (this is all you type)
  ip a                               my address (vs the install sheet)
  ip route get 10.50.1.31            the source address the camera sees
  curl -i http://10.50.1.31/         the status line (403?)
  sudo ip addr flush dev eth0        drop the wrong address
  sudo ip addr add 10.50.0.50/24 dev eth0      add the right one
  sudo ip route add default via 10.50.0.254    flushing removed it

## 1 OBSERVE
SAY: "The camera answers, so the path is fine. 403 means it doesn't like
      WHO is asking. What is my address?"
  $ ip a
    => a = address: every network card and its IP
    => eth0 ... inet 10.50.0.150/24        <- install sheet says .50
  $ cat ~/install-sheet.txt
    => edge-nvr-03  10.50.0.50/24  gateway 10.50.0.254
    => camera1 ... web UI :80 (accepts the NVR, 10.50.0.50, only)
  $ curl -i http://10.50.1.31/
    => -i = also show the reply's status line and headers
    => HTTP/1.0 403 Forbidden
    => 403 Forbidden

## 2 NARROW
SAY: "Box has .150, the camera only accepts .50. The reservation didn't
      stick after the reboot. Which address does the camera see?"
  $ ip route get 10.50.1.31
    => "how would you send a packet to 10.50.1.31?"
    => 10.50.1.31 via 10.50.0.254 dev eth0 src 10.50.0.150
    => via = the gateway   src = MY address as the camera sees it

## 3 ACT
SAY: "I'll replace the address, and re-add the default route because
      flushing removes it."
  $ sudo ip addr flush dev eth0
    => flush = remove every IPv4 address from eth0 (no output = ok)
    => it also removes the routes that used them, the default too
  $ sudo ip addr add 10.50.0.50/24 dev eth0
    => /24 = the first 3 numbers are the local network: this is what
       tells the box the gateway 10.50.0.254 is next door
  $ sudo ip route add default via 10.50.0.254
    => default = where everything off this subnet goes
  Then persist it in the interface config or DHCP reservation; a live
  change dies at reboot

## 4 VERIFY
SAY: "Confirm the source address the camera will see, then the real
      thing."
  $ ip route get 10.50.1.31
    => 10.50.1.31 via 10.50.0.254 dev eth0 src 10.50.0.50
  $ curl -i http://10.50.1.31/
    => HTTP/1.0 200 OK
    => camera1 - RTSP relay OK - stream 1080p30
  $ check

TRAP
  - adding .50 next to .150 leaves .150 as the primary (source) address:
    still 403.
  - Wrong prefix (/32) means no on-link route to the gateway: nothing
    leaves the box.
  - Forgetting the default route after the flush: curl says
    `curl: (7) Failed to connect ... Couldn't connect to server`.

DO IT BETTER
  - 403 = the far end answered: check the box's OWN identity, not the
    route.
  - `ip route get` shows the source address the camera will see.
  - Flushing removes the default route: re-add it, then persist both.
