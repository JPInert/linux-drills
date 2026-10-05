# "make the box match the template": a 10.40.2.1 alias on eth1, so the Oak Glen range 'works'
ip addr add 10.40.2.1/24 dev eth1
systemctl restart dnsmasq
sleep 8
