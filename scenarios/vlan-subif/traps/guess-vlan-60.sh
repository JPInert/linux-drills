# guessed the other VLAN the trunk allows (60 = sensors), done properly: still not the camera VLAN
sed -i 's/^Id=5$/Id=60/' /etc/systemd/network/20-eth1.50.netdev
ip link delete eth1.50
systemctl restart systemd-networkd
sleep 6
