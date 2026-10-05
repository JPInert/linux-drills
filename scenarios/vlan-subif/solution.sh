set -e
sudo journalctl -u nvr-recorder --no-pager | tail -2
ip a show eth1.50
ping -c 2 -W 1 10.50.50.31 || true
ip neigh
ip -d link show eth1.50
networkctl status eth1.50 --no-pager | head -6
cat /etc/systemd/network/20-eth1.50.netdev
sudo sed -i 's/^Id=5$/Id=50/' /etc/systemd/network/20-eth1.50.netdev
sudo ip link delete eth1.50
sudo systemctl restart systemd-networkd
for _ in $(seq 1 20); do ip -4 addr show eth1.50 2>/dev/null | grep -q 10.50.50.2 && break; sleep 0.5; done
ip -d link show eth1.50 | grep 'id 50'
ping -c 2 10.50.50.31
sleep 6
sudo journalctl -u nvr-recorder --no-pager | tail -2
