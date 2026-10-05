# dhcp-cam-vlan: new WiFi cameras 'get no IP'

WEAK SPOT    "No IP = the WiFi / the access point." If the static cameras
             on the same WiFi work, the air and the AP are fine. No IP is
             the DHCP SERVER's answer, and its log says why.
LOCAL-FIRST  This box is the DHCP server (dnsmasq). Its journal shows
             every request that arrives and what it did with it.

THE SHORT FORMS (this is all you type)
  systemctl status dnsmasq            is the DHCP server running
  sudo journalctl -u dnsmasq | tail   what it did with the requests
  ip a show eth1                      the subnet the cameras are on
  cat /etc/dnsmasq.d/cam-wifi.conf    what it hands out
  cat ~/install-sheet.txt             what it SHOULD hand out
  sudo nano /etc/dnsmasq.d/cam-wifi.conf        fix the addresses
  sudo dnsmasq --test                 syntax check before a restart
  sudo systemctl restart dnsmasq      it reads its config at start
  cat /var/lib/misc/dnsmasq.leases    who got which address

## 1 OBSERVE
SAY: "New cameras get no address, old static ones work. So the WiFi is
      up. I'll ask the DHCP server on this box what it sees."
  $ systemctl --failed
    => fwupd-refresh.service failed: a firmware metadata check, offline.
       Not DHCP. Ignored.
  $ systemctl status dnsmasq
    => Active: active (running) ... enabled: it runs, and at boot too
  $ sudo journalctl -u dnsmasq | tail
    => -u = only this unit's log   tail = the last 10 lines
    => DHCP, IP range 10.40.2.100 -- 10.40.2.199, lease time 12h
    => DHCP, sockets bound exclusively to interface eth1
    => no address range available for DHCP request via eth1  (repeats)
SAY: "The requests ARRIVE on eth1, so the WiFi and the AP deliver them.
      The server has no range that fits eth1."

## 2 NARROW
  $ ip a show eth1
    => inet 10.50.2.1/24 ... eth1       (the camera WiFi segment)
  $ cat /etc/dnsmasq.d/cam-wifi.conf
    => # from the site template (Oak Glen), 2026-09-25
    => interface=eth1
    => dhcp-range=10.40.2.100,10.40.2.199,255.255.255.0,12h
    => dhcp-option=option:router,10.40.2.1
    => dhcp-option=option:dns-server,10.40.2.1
    => three addresses from another site. eth1 is 10.50.2.x, so no
       range matches, so nothing is ever offered
  $ cat ~/install-sheet.txt
    => DHCP pool  10.50.2.100 - 10.50.2.199  (router/DNS = 10.50.2.1)
    => static cameras 10.50.2.11 - 10.50.2.19  (keep the pool off them)

## 3 ACT
SAY: "I'll fix all three lines, not just the range: with the range
      alone the cameras would get an address and the wrong gateway."
  $ sudo nano /etc/dnsmasq.d/cam-wifi.conf
    => change 10.40.2. to 10.50.2. on the dhcp-range, router and
       dns-server lines; save (Ctrl+O, Enter), quit (Ctrl+X)
    => the same edit in one line, no editor:
       sudo sed -i 's/10\.40\.2\./10.50.2./g' FILE
       (-i = in place, s/old/new/g = replace every match on each line,
       \. = a real dot)
  $ sudo dnsmasq --test
    => --test = only check the config
    => dnsmasq: syntax check OK.   (dnsmasq is in /usr/sbin: sudo)
  $ sudo systemctl restart dnsmasq

## 4 VERIFY
SAY: "Proof: the range it serves now, then the cameras' own leases."
  $ sudo journalctl -u dnsmasq | grep "IP range" | tail -1
    => grep "IP range" = only lines with that text
    => DHCP, IP range 10.50.2.100 -- 10.50.2.199, lease time 12h
  $ sudo journalctl -u dnsmasq | grep DHCPACK | tail -2
    => nothing yet? the cameras retry every few seconds and dnsmasq
       pings a new address first (~3 s): give it 10 s, run it again
    => DHCPACK(eth1) 10.50.2.155 3c:ef:8c:1a:2b:01 wificam-rm207
    => DHCPACK(eth1) 10.50.2.156 3c:ef:8c:1a:2b:02 wificam-rm212
    => ACK = the server confirmed the lease (DISCOVER, OFFER, REQUEST,
       ACK: the four DHCP steps)
  $ cat /var/lib/misc/dnsmasq.leases
    => ... 3c:ef:8c:1a:2b:02 10.50.2.156 wificam-rm212 *
    => ... 3c:ef:8c:1a:2b:01 10.50.2.155 wificam-rm207 *
  $ systemctl is-enabled dnsmasq
    => enabled   (it starts at boot)
  $ check

TRAP
  - Swapping the access point: the requests already reach the box.
  - Restarting dnsmasq alone: it re-reads the same wrong range.
  - Fixing only dhcp-range: the cameras get 10.50.2.x but are told the
    gateway and DNS are 10.40.2.1, which does not exist here.
  - Adding 10.40.2.1 to eth1 so the old range "fits": the cameras land
    on a subnet the NVR and the sheet know nothing about.
  - A pool of the whole /24: it overlaps the static cameras .11-.19.
  - Running dnsmasq by hand and disabling the service: gone at reboot.

DO IT BETTER
  - "No IP": read the DHCP server's log first. Request seen = the
    network is fine; the server's answer tells you why.
  - A config copied from another site: grep it for that site's
    numbers (grep 10.40 FILE) and fix every one.
  - ESCALATE / TELL THE CUSTOMER: "Cameras rm207/rm212 now lease
    10.50.2.155/.156. The dnsmasq config on edge-nvr-03 was copied from
    Oak Glen with 10.40.2.x addresses; fixed. Please fix the template."
