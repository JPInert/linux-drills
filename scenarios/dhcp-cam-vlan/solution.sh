set -e
systemctl status dnsmasq --no-pager | head -5
sudo journalctl -u dnsmasq --no-pager | tail -5
ip a show eth1
cat /etc/dnsmasq.d/cam-wifi.conf
sudo sed -i 's/10\.40\.2\./10.50.2./g' /etc/dnsmasq.d/cam-wifi.conf
sudo dnsmasq --test
sudo systemctl restart dnsmasq
sleep 6
sudo journalctl -u dnsmasq --no-pager | grep 'IP range' | tail -1
sudo journalctl -u dnsmasq --no-pager | grep DHCPACK | tail -2
cat /var/lib/misc/dnsmasq.leases
systemctl is-enabled dnsmasq
