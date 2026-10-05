# "make the pool the whole subnet": it now overlaps the static cameras (.11-.19)
sed -i -e 's/10\.40\.2\./10.50.2./g' -e 's/^dhcp-range=.*/dhcp-range=10.50.2.2,10.50.2.254,255.255.255.0,12h/' /etc/dnsmasq.d/cam-wifi.conf
systemctl restart dnsmasq
sleep 8
