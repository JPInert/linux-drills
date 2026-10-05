# chasing the network: the firewall is not the problem, nothing listens
iptables -F; iptables -t nat -F; ip neigh flush all
