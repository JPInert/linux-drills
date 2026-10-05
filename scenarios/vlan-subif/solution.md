# vlan-subif: camera VLAN interface UP, right IP, wrong VLAN id

WEAK SPOT    "It's UP and has the right IP, so the box is fine." UP and
             an address are layer 1 and 3. On a trunk the VLAN TAG
             decides who hears you, and an interface's NAME (eth1.50)
             is just a label: the id is a separate setting.
LOCAL-FIRST  ip neigh, ip -d link and one tcpdump prove it from the box;
             the switch is fine and nobody needs to go on site.

THE SHORT FORMS (this is all you type)
  sudo journalctl -u nvr-recorder | tail -4    what the recorder gets
  ip a show eth1.50                     UP, address (looks fine)
  ping -c 3 10.50.50.31                 "Destination Host Unreachable"
  ip neigh                              ARP: FAILED = no MAC answer
  ip -d link show eth1.50               the REAL vlan id (-d details)
  sudo tcpdump -eni eth1 -c 3           the tag on the wire
  networkctl status eth1.50             which files build it
  sudo nano /etc/systemd/network/20-eth1.50.netdev      fix Id=
  sudo ip link delete eth1.50           drop the wrongly tagged link
  sudo systemctl restart systemd-networkd     rebuild it from the file

## 1 OBSERVE
SAY: "Both cameras down after a reimage. Sweep the box, then ask the
      recorder what exactly fails."
  $ systemctl --failed
    => fwupd-refresh.service failed: a firmware metadata check, offline.
       Not cameras. Ignored.
  $ sudo journalctl -u nvr-recorder | tail -4
    => -u = only this unit's log   tail -4 = the last 4 lines
    => camera1: RTSP connect to 10.50.50.31:554 failed: No route to
       host, reconnecting    (same for camera2)
    => "No route to host" on a LOCAL subnet = nobody answered ARP
  $ ip a show eth1.50
    => eth1.50@eth1: <...,UP,LOWER_UP>  inet 10.50.50.2/24
    => looks exactly like the sheet. This is what Tier 1 saw.

## 2 NARROW
  $ ping -c 3 10.50.50.31
    => -c 3 = send 3 pings then stop
    => From 10.50.50.2 icmp_seq=1 Destination Host Unreachable
    => the box ITSELF says unreachable: it could not find a MAC
  $ ip neigh
    => neigh = the ARP table: IP -> MAC of everything nearby
    => 10.50.50.31 dev eth1.50 FAILED
    => 10.50.50.32 dev eth1.50 FAILED   (INCOMPLETE = still asking)
    => asked "who has 10.50.50.31?", got no answer: layer 2
SAY: "Same subnet, link up, no ARP answers from two cameras at once.
      That is the VLAN, not the cameras."
  $ ip -d link show eth1.50
    => -d = details (for a VLAN: the id it tags with)
    => vlan protocol 802.1Q id 5 <REORDER_HDR> ...
    => id 5, not 50. The NAME says 50; the tag is 5
  $ cat ~/install-sheet.txt
    => eth1.50  camera VLAN 50  10.50.50.2/24
    => switch Gi1/0/24: trunk, allowed VLANs 50, 60
  $ sudo tcpdump -eni eth1 -c 3
    => -e = print the link header (MACs, vlan tag)  -n = no name lookup
    => -i eth1 = listen on eth1  -c 3 = stop after 3 packets
    => ... ethertype 802.1Q (0x8100) ...: vlan 5, ... ARP, Request
       who-has 10.50.50.31 tell 10.50.50.2
    => the box shouts on VLAN 5; the switch only carries 50 and 60
  $ networkctl status eth1.50
    => Network File: /etc/systemd/network/30-cam-vlan.network
    => VLan Id: 5
  $ cat /etc/systemd/network/20-eth1.50.netdev
    => [NetDev] Name=eth1.50  Kind=vlan
    => [VLAN] Id=5            <- the reimage's typo

## 3 ACT
SAY: "Fix the id in the file networkd builds it from. networkd will
      not re-tag a VLAN link that already exists, so I delete the link
      and restart networkd to rebuild it from the file."
  $ sudo nano /etc/systemd/network/20-eth1.50.netdev
    => change Id=5 to Id=50; save (Ctrl+O, Enter), quit (Ctrl+X)
  $ sudo ip link delete eth1.50
    => removes the link (the cameras are unreachable anyway)
  $ sudo systemctl restart systemd-networkd
    => networkd re-reads the .netdev and creates eth1.50 with id 50
    => (networkctl reload alone keeps the old id: tested)

## 4 VERIFY
SAY: "Proof: the tag, the neighbours, then what the RECORDER gets."
  $ ip -d link show eth1.50
    => vlan protocol 802.1Q id 50 ...
  $ ping -c 3 10.50.50.31
    => 3 packets transmitted, 3 received, 0% packet loss
  $ sudo journalctl -u nvr-recorder | tail -2
    => camera1: DESCRIBE rtsp://10.50.50.31:554/... -> RTSP/1.0 200 OK,
       stream up      (camera2 the same)
  $ check

TRAP
  - Sending the switch vendor: the box tags VLAN 5, a VLAN the trunk
    does not carry. The switch is doing exactly what it was set to.
  - Trusting the name: eth1.50 can carry any id. ip -d link shows it.
  - Editing Id= and running networkctl reload / restarting networkd
    WITHOUT deleting the link: the old link keeps id 5.
  - Rebuilding the link by hand (ip link add ... id 50) only: right
    now, but the .netdev puts id 5 back at the next boot.
  - Putting 10.50.50.2 on eth1 itself (untagged): the port is
    tagged-only, nothing answers.
  - Guessing VLAN 60: that is the sensor VLAN on the same trunk.

DO IT BETTER
  - "No route to host" / "Destination Host Unreachable" from the box
    itself on its OWN subnet = ARP failed: ip neigh, then layer 2.
  - ip -d link for any VLAN, bond or bridge: the details, not the name.
  - ESCALATE / TELL THE CUSTOMER: "Golden image v7 set the camera VLAN
    id to 5 instead of 50 on eth1.50. Fixed on edge-nvr-03 (file +
    live); please fix the image before it reaches other boxes. The
    switch was fine."
