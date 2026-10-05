# chain-static-route: sensor dashboard blank after the config push

WEAK SPOT    "Only the sensors broke, so it's the sensors (or the Wi-Fi)."
             One network down while another works = a ROUTE question
             first: which way does THIS box send traffic for it?
LOCAL-FIRST  ip r and ip route get answer it on the box. The config push
             carried a route for the OLD sensor subnet.

THE SHORT FORMS (this is all you type)
  sudo journalctl -u sensor-poller | tail     what the poller gets
  ip r                            my routes
  ip route get 10.60.0.20         the exact way out for one address
  cat ~/install-sheet.txt         what the routes SHOULD be
  networkctl status eth1          which file configures eth1
  sudo nano /etc/systemd/network/20-sensor-uplink.network
  sudo networkctl reload          apply the .network files now
  curl http://10.60.0.20/status   the hub itself answers

## 1 OBSERVE
SAY: "Dashboard blank, cameras fine. Sweep the box, then ask the
      poller what it is getting."
  $ systemctl --failed
    => fwupd-refresh.service failed: a firmware metadata check that
       can't reach the internet. Not sensors. Ignored.
  $ systemctl status sensor-poller
    => Active: active (running): the software is up
  $ sudo journalctl -u sensor-poller | tail
    => -u = only this unit's log   tail = the last 10 lines
    => bed-exit hub 10.60.0.20: poll failed: timed out after 2s
    => door hub 10.60.0.21: poll failed: timed out after 2s
  $ ip a
    => eth1 inet 10.60.255.2/29: the sensor uplink has its address
    => gwdrop-sim is the LAB's stand-in for the gateway's dead end
       (a real box has none): ignore it
  $ cat ~/install-sheet.txt
    => sensor router 10.60.255.1  routes the SENSOR VLAN 10.60.0.0/24
       (the default gateway does NOT know it)
    => retired: sensor VLAN 10.61.0.0/24

## 2 NARROW
SAY: "Timeouts to both hubs. Which way does the box send packets for
      10.60.0.x?"
  $ ip r
    => r = route: where the box sends traffic
    => default via 172.17.0.1 dev eth0
    => 10.60.255.0/29 dev eth1 ... src 10.60.255.2
    => 10.61.0.0/24 via 10.60.255.1 dev eth1 proto static
    => no line for 10.60.0.0/24. 10.61 is the RETIRED subnet: it looks
       like the sensor route at a glance, but it is the wrong network
  $ ip route get 10.60.0.20
    => route get = which route this one address would use
    => 10.60.0.20 via 172.17.0.1 dev eth0 ...
    => out the DEFAULT gateway, which has no path to the sensors
  $ ping -c 3 10.60.255.1
    => -c 3 = send 3 pings then stop
    => 3 received: the sensor router itself is up, one hop away
SAY: "The sensor router is up; the box just never sends sensor
      traffic to it. Which file set the routes on eth1?"
  $ networkctl status eth1
    => Network File: /etc/systemd/network/20-sensor-uplink.network
    => State: routable (configured): systemd-networkd manages eth1
  $ cat /etc/systemd/network/20-sensor-uplink.network
    => # site-standard v3 (applied 2026-09-24 by config push SS-3)
    => [Route]
    => Destination=10.61.0.0/24      <- the pre-2025 subnet
    => Gateway=10.60.255.1

## 3 ACT
SAY: "I'll fix the route in the file networkd reads, so it survives a
      reboot, and have networkd apply it now."
  $ sudo nano /etc/systemd/network/20-sensor-uplink.network
    => change Destination=10.61.0.0/24 to Destination=10.60.0.0/24
    => save (Ctrl+O, Enter), quit (Ctrl+X)
  $ sudo networkctl reload
    => re-reads every .network file and reconfigures the links
    => (without sudo: "Access denied")
  Live-only alternative (lost at reboot):
    sudo ip route add 10.60.0.0/24 via 10.60.255.1 dev eth1

## 4 VERIFY
SAY: "Proof: the route, the path, the hub, then what the POLLER gets."
  $ ip r
    => (right after the reload eth1's routes can be missing for a
       second while networkd reconfigures it: run ip r again)
    => 10.60.0.0/24 via 10.60.255.1 dev eth1 proto static
    => proto static = networkd put it there from the file: it will be
       there after a reboot too (a hand-typed route has no proto static)
  $ ip route get 10.60.0.20
    => 10.60.0.20 via 10.60.255.1 dev eth1 src 10.60.255.2
  $ curl http://10.60.0.20/status
    => {"hub": "bed-exit hub", ... "sensors": 14, "online": 14, ...}
  $ sudo journalctl -u sensor-poller | tail -2
    => (the poller tries every few seconds: old failures first, then)
    => bed-exit hub 10.60.0.20: OK 14/14 sensors online
    => door hub 10.60.0.21: OK 9/9 sensors online
  $ check

TRAP
  - Reading "10.61.0.0/24 via 10.60.255.1" as the sensor route: read
    every digit against the sheet.
  - Routing 10.60.0.0/24 via the default gateway: it has no path to
    the sensor VLAN (the sheet says so); still timeouts.
  - ip route add only: works now, gone at the next reboot.
  - A NEW .network file for eth1: networkd uses only the FIRST file (by
    name) that matches a link, so 30-anything.network is ignored.
  - Editing the file without networkctl reload: nothing changes until
    a reboot, and you have not proved the file works.

DO IT BETTER
  - One network down, another up: ip route get ADDRESS first. It names
    the exact next hop in one line.
  - After a config push, diff the pushed values against the sheet, not
    against what "looks like" a route.
  - ESCALATE / TELL THE CUSTOMER: "Config push SS-3 carried the retired
    sensor subnet 10.61.0.0/24 in the eth1 route. Corrected to
    10.60.0.0/24 via 10.60.255.1 on edge-nvr-03; please fix the
    site-standard template before it is pushed to other boxes."
