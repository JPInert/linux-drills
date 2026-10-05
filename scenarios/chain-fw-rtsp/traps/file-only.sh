# right line removed from rules.v4, never loaded: the live firewall still drops RTSP
sed -i '/--dport 554 -j DROP/d' /etc/iptables/rules.v4
sleep 4
