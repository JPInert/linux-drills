/usr/local/lib/drill/lived-in
cat > /home/tech/install-sheet.txt <<'SHEET'
NORTHGATE GARAGE - CAMERA WIFI SEGMENT                           (rev B, 2026-09, J. Ortiz)

  edge-nvr-03   eth1   10.50.2.1/24   gateway + DHCP server for the camera WiFi segment
  DHCP pool            10.50.2.100 - 10.50.2.199   (12 h leases, router/DNS = 10.50.2.1)
  static cameras       10.50.2.11 - 10.50.2.19     (older PoE/WiFi cameras, set on the camera)

  new today            wificam-rm207   3c:ef:8c:1a:2b:01   (DHCP)
                       wificam-rm212   3c:ef:8c:1a:2b:02   (DHCP)
SHEET
chown tech:tech /home/tech/install-sheet.txt
cat > /etc/dnsmasq.d/cam-wifi.conf <<'CONF'
# camera WiFi segment: DHCP only (no DNS: port=0)
# from the site template (Oak Glen), 2026-09-25
port=0
interface=eth1
bind-interfaces
dhcp-authoritative
dhcp-range=10.40.2.100,10.40.2.199,255.255.255.0,12h
dhcp-option=option:router,10.40.2.1
dhcp-option=option:dns-server,10.40.2.1
log-dhcp
CONF
systemctl enable dnsmasq >/dev/null 2>&1
systemctl restart dnsmasq
systemctl is-active --quiet dnsmasq
for _ in $(seq 1 40); do journalctl -q -u dnsmasq 2>/dev/null | grep -q 'no address range available' && break; sleep 0.5; done
journalctl -q -u dnsmasq | grep -q 'no address range available'
