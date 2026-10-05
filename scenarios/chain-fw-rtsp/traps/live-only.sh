# right rule, removed live only: rules.v4 still has it, so it is back at the next boot
iptables -D CAM-EGRESS -p tcp --dport 554 -j DROP
sleep 4
