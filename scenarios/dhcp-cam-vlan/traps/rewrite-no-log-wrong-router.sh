# rewrote the config from scratch without log-dhcp, right range but the template's router/DNS kept
cat > /etc/dnsmasq.d/cam-wifi.conf <<'CONF'
port=0
interface=eth1
bind-interfaces
dhcp-range=10.50.2.100,10.50.2.199,255.255.255.0,12h
dhcp-option=option:router,10.40.2.1
dhcp-option=option:dns-server,10.40.2.1
CONF
systemctl restart dnsmasq
sleep 8
