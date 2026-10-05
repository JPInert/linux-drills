set -e
sudo journalctl -u sensor-poller --no-pager | tail -3
ip r
ip route get 10.60.0.20
sudo sed -i 's#^Destination=10.61.0.0/24#Destination=10.60.0.0/24#' /etc/systemd/network/20-sensor-uplink.network
sudo networkctl reload
networkctl status eth1 --no-pager | head -5
for _ in $(seq 1 20); do ip r | grep -q '^10.60.0.0/24 via 10.60.255.1' && break; sleep 0.5; done
ip r
sleep 6
curl -s -m 3 http://10.60.0.20/status
sudo journalctl -u sensor-poller --no-pager | tail -2
