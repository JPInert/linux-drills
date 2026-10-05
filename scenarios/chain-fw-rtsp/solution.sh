set -e
sudo journalctl -u nvr-recorder --no-pager | tail -4
ping -c 2 10.50.1.31
curl -s -m 3 http://10.50.1.31/
! nc -zv -w 3 10.50.1.31 554
sudo iptables -L OUTPUT -n -v
sudo iptables -L CAM-EGRESS -n -v --line-numbers
systemctl status netfilter-persistent --no-pager | head -8
sudo grep -n 554 /etc/iptables/rules.v4
sudo sed -i '/-A CAM-EGRESS -p tcp --dport 554 -j DROP/d' /etc/iptables/rules.v4
sudo iptables-restore --test /etc/iptables/rules.v4
sudo systemctl restart netfilter-persistent
sudo iptables -L CAM-EGRESS -n --line-numbers
nc -zv -w 3 10.50.1.31 554
sleep 5
sudo journalctl -u nvr-recorder --no-pager | tail -3
