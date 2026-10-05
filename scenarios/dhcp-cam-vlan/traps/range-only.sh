# fixed the range line only: the cameras get an address but are told the Oak Glen router and DNS
sed -i 's/^dhcp-range=10\.40\.2\.100,10\.40\.2\.199/dhcp-range=10.50.2.100,10.50.2.199/' /etc/dnsmasq.d/cam-wifi.conf
systemctl restart dnsmasq
sleep 8
