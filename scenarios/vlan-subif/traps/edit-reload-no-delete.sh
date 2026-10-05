# right Id in the .netdev, applied with reload + restart: networkd never changes the id of a VLAN
# link that already exists, so eth1.50 is still VLAN 5 until the link is deleted
sed -i 's/^Id=5$/Id=50/' /etc/systemd/network/20-eth1.50.netdev
networkctl reload
systemctl restart systemd-networkd
sleep 6
