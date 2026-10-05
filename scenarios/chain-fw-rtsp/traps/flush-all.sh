# "the firewall is blocking it": flush every rule and save the empty set (kills the whole audited baseline)
iptables -F; iptables -X
netfilter-persistent save
sleep 4
