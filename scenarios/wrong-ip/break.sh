. /drill-lab/baseline.sh
# after the "power blip" the box grabbed a fallback address instead of its reservation
ip addr flush dev eth0
ip addr add 10.50.0.150/24 dev eth0
ip route replace default via 10.50.0.254
