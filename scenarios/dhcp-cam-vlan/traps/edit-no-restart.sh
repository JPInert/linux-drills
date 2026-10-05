# right addresses in the file, but dnsmasq read its config at start
sed -i 's/10\.40\.2\./10.50.2./g' /etc/dnsmasq.d/cam-wifi.conf
sleep 8
