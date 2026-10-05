# ---- the box ----
ip -4 route show default | head -1 > /var/lib/drill/.default-route; chmod 0600 /var/lib/drill/.default-route
/usr/local/lib/drill/lived-in
cat > /home/tech/install-sheet.txt <<'SHEET'
NORTHGATE GARAGE - EDGE BOX NETWORK SHEET                        (rev D, 2025-11, J. Ortiz)

  edge-nvr-03  eth0  camera/LAN side (Docker-managed on this unit, leave alone)
               eth1  sensor uplink   10.60.255.2/29
  sensor router      10.60.255.1     routes the SENSOR VLAN 10.60.0.0/24
                                     (the default gateway does NOT know it)
  bed-exit hub       10.60.0.20      http://10.60.0.20/status
  door hub           10.60.0.21      http://10.60.0.21/status

  retired: sensor VLAN 10.61.0.0/24 (renumbered to 10.60.0.0/24 in 2025-11)
SHEET
chown tech:tech /home/tech/install-sheet.txt
# networkd owns eth1 only; it must not touch Docker's eth0 routes
install -d /etc/systemd/networkd.conf.d
cat > /etc/systemd/networkd.conf.d/10-leave-foreign.conf <<'CONF'
# eth0 is configured by Docker, not by networkd: leave routes and rules we did not make alone
[Network]
ManageForeignRoutes=no
ManageForeignRoutingPolicyRules=no
CONF
cat > /etc/systemd/network/20-sensor-uplink.network <<'NET'
# site-standard v3 (applied 2026-09-24 by config push SS-3)
# edge box: sensor uplink NIC
[Match]
Name=eth1

[Network]
Address=10.60.255.2/29
LinkLocalAddressing=no
IPv6AcceptRA=no

[Route]
# sensor VLAN, via the sensor router
Destination=10.61.0.0/24
Gateway=10.60.255.1
NET
systemctl enable --now systemd-networkd >/dev/null 2>&1
# ---- the service ----
id sensorpoll >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin -M sensorpoll
install -d /opt/sensor-poller /etc/sensor-poller
install -m 0755 /drill/mock/poller.py /opt/sensor-poller/poller.py
cat > /etc/sensor-poller/poller.conf <<'CONF'
# sensor-poller: hubs on the sensor VLAN (Northgate Garage)
HUB=bed-exit hub 10.60.0.20
HUB=door hub 10.60.0.21
POLL_SECONDS=3
TIMEOUT_SECONDS=2
CONF
cat > /etc/systemd/system/sensor-poller.service <<'UNIT'
[Unit]
Description=Sensor poller (bed-exit / door hubs -> care dashboard)
After=network-online.target

[Service]
ExecStart=/usr/bin/python3 /opt/sensor-poller/poller.py
User=sensorpoll
RuntimeDirectory=sensor-poller
RuntimeDirectoryPreserve=yes
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
for _ in $(seq 1 40); do ip -4 addr show eth1 | grep -q 10.60.255.2 && break; sleep 0.25; done
ip -4 addr show eth1 | grep -q 10.60.255.2
systemctl enable --now sensor-poller >/dev/null 2>&1
for _ in $(seq 1 40); do grep -q '"no data"' /run/sensor-poller/dashboard.json 2>/dev/null && break; sleep 0.5; done
grep -q '"no data"' /run/sensor-poller/dashboard.json
