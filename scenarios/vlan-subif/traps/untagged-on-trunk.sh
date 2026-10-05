# "skip the VLAN, put the address on eth1": the switch port is tagged-only, nothing answers untagged
ip addr del 10.50.50.2/24 dev eth1.50
ip addr add 10.50.50.2/24 dev eth1
sleep 6
