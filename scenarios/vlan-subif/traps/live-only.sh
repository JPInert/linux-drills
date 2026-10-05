# rebuilt eth1.50 by hand with the right id: works now, the .netdev still says Id=5 at the next boot
ip link delete eth1.50
ip link add link eth1 name eth1.50 type vlan id 50
ip addr add 10.50.50.2/24 dev eth1.50
ip link set eth1.50 up
sleep 6
