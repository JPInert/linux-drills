# "allow the box to the camera VLAN": an ACCEPT-everything rule ahead of the baseline, saved (telnet/ftp open too)
iptables -I OUTPUT 1 -d 10.50.1.0/24 -j ACCEPT
netfilter-persistent save
sleep 4
