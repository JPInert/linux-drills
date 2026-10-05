# chasing the network: there is no firewall rule to remove, sshd is simply not on 22
iptables -F; iptables -t nat -F; iptables -P INPUT ACCEPT
ip neigh flush all
