# "make 22 work" with a firewall redirect, from outside AND from the box itself
iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-ports 2222
iptables -t nat -A OUTPUT -o lo -p tcp --dport 22 -j REDIRECT --to-ports 2222
