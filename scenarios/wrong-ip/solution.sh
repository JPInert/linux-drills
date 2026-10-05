set -e
sudo ip addr flush dev eth0
sudo ip addr add 10.50.0.50/24 dev eth0
sudo ip route add default via 10.50.0.254
sleep 1
