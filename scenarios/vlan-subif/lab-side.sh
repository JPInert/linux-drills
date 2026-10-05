# ---- LAB STAND-IN: the switch trunk port and camera1/camera2 behind it on VLAN 50 (10.50.50.31/.32),
# in their own container and network namespace. Tagged frames with any other VLAN id reach nothing.
ip link set swport-peer name eth0
ip link set lo up
ip link set eth0 up
ip link add link eth0 name eth0.50 type vlan id 50
ip addr add 10.50.50.31/24 dev eth0.50
ip addr add 10.50.50.32/24 dev eth0.50
ip link set eth0.50 up
setsid -f /usr/bin/python3 /drill/mock/cameras.py > /var/log/cameras.log 2>&1 < /dev/null
for _ in $(seq 1 20); do ss -tln | grep -q '10.50.50.32:554' && break; sleep 0.25; done
ss -tln | grep -q '10.50.50.32:554'
