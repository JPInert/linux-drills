# ---- the box ----
/usr/local/lib/drill/lived-in
cat > /home/tech/install-sheet.txt <<'SHEET'
NORTHGATE GARAGE - EDGE BOX NETWORK SHEET                        (rev E, 2026-03, J. Ortiz)

  edge-nvr-03  eth0      management (Docker-managed on this unit, leave alone)
               eth1      TRUNK to switch port Gi1/0/24 (tagged only, no untagged VLAN)
               eth1.50   camera VLAN 50   10.50.50.2/24
  camera1      10.50.50.31   rtsp://10.50.50.31:554/Streaming/Channels/101
  camera2      10.50.50.32   rtsp://10.50.50.32:554/Streaming/Channels/101

  switch Gi1/0/24:  switchport mode trunk, allowed VLANs 50 (cameras), 60 (sensors)
SHEET
chown tech:tech /home/tech/install-sheet.txt
install -d /etc/systemd/networkd.conf.d
cat > /etc/systemd/networkd.conf.d/10-leave-foreign.conf <<'CONF'
# eth0 is configured by Docker, not by networkd: leave routes and rules we did not make alone
[Network]
ManageForeignRoutes=no
ManageForeignRoutingPolicyRules=no
CONF
cat > /etc/systemd/network/10-trunk.network <<'NET'
# reimaged 2026-09-24 (golden image v7): trunk NIC to the switch
[Match]
Name=eth1

[Network]
VLAN=eth1.50
LinkLocalAddressing=no
IPv6AcceptRA=no
NET
cat > /etc/systemd/network/20-eth1.50.netdev <<'NET'
# camera VLAN on the trunk
[NetDev]
Name=eth1.50
Kind=vlan

[VLAN]
Id=5
NET
cat > /etc/systemd/network/30-cam-vlan.network <<'NET'
[Match]
Name=eth1.50

[Network]
Address=10.50.50.2/24
LinkLocalAddressing=no
IPv6AcceptRA=no
NET
systemctl enable --now systemd-networkd >/dev/null 2>&1
for _ in $(seq 1 40); do ip -4 addr show eth1.50 2>/dev/null | grep -q 10.50.50.2 && break; sleep 0.25; done
ip -d link show eth1.50 | grep -q 'vlan protocol 802.1Q id 5 '
# ---- the recorder ----
id nvr >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin -M nvr
install -d /opt/nvr-recorder /etc/nvr-recorder
install -m 0755 /drill/mock/recorder.py /opt/nvr-recorder/recorder.py
cat > /etc/nvr-recorder/cameras.conf <<'CONF'
# nvr-recorder: RTSP sources for vehicle counting (Northgate Garage)
#       name    url                                              user  password
CAMERA=camera1 rtsp://10.50.50.31:554/Streaming/Channels/101 nvr HR-cam1-4471
CAMERA=camera2 rtsp://10.50.50.32:554/Streaming/Channels/101 nvr HR-cam2-8810
RETRY_SECONDS=3
CONNECT_TIMEOUT=5
CONF
chown root:nvr /etc/nvr-recorder/cameras.conf; chmod 0640 /etc/nvr-recorder/cameras.conf
cat > /etc/systemd/system/nvr-recorder.service <<'UNIT'
[Unit]
Description=NVR recorder (camera RTSP sessions -> vehicle-count pipeline)
After=network-online.target

[Service]
ExecStart=/usr/bin/python3 /opt/nvr-recorder/recorder.py
User=nvr
Group=nvr
RuntimeDirectory=nvr-recorder
RuntimeDirectoryPreserve=yes
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now nvr-recorder >/dev/null 2>&1
for _ in $(seq 1 40); do grep -q '"camera2"' /run/nvr-recorder/status.json 2>/dev/null && break; sleep 0.5; done
grep -A2 '"camera1"' /run/nvr-recorder/status.json | grep -q reconnecting
