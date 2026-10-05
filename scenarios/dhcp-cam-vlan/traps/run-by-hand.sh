# fixed config, but dnsmasq run by hand in the background and the service stopped + disabled
sed -i 's/10\.40\.2\./10.50.2./g' /etc/dnsmasq.d/cam-wifi.conf
systemctl disable --now dnsmasq
dnsmasq --conf-file=/etc/dnsmasq.d/cam-wifi.conf
sleep 8
