# ---- LAB STAND-IN: the sensor router (10.60.255.1) and the two hubs behind it (10.60.0.20/.21),
# in their own container and network namespace.
ip link set srtr-peer name eth0
ip addr add 10.60.255.1/29 dev eth0
ip link set lo up
ip addr add 10.60.0.20/32 dev lo
ip addr add 10.60.0.21/32 dev lo
ip link set eth0 up
setsid -f /usr/bin/python3 /drill/mock/sensors.py > /var/log/sensor-hubs.log 2>&1 < /dev/null
for _ in $(seq 1 20); do ss -tln | grep -q '10.60.0.21:80' && break; sleep 0.25; done
ss -tln | grep -q '10.60.0.21:80'
