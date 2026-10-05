ip addr flush dev eth0; ip addr add 10.50.0.50/32 dev eth0; ip route add 10.50.0.254 dev eth0; ip route add default via 10.50.0.254
