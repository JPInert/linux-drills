# right route, typed live only: networkd's file still lacks it, so it is gone at the next boot
ip route add 10.60.0.0/24 via 10.60.255.1 dev eth1
sleep 5
