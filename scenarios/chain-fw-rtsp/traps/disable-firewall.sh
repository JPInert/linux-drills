# "turn the firewall off": disable the baseline unit and flush the live rules
systemctl disable --now netfilter-persistent
netfilter-persistent flush
sleep 4
