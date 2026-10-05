# ---- LAB STAND-IN: the WiFi access point's side, with the two new cameras (DHCP clients), in their own
# container and network namespace.
ip link set wifi-ap-peer name eth0
ip link set lo up
ip link set eth0 up
setsid -f /usr/bin/python3 /drill/mock/dhcpsim.py cams eth0 > /var/log/wifi-cams.log 2>&1 < /dev/null
