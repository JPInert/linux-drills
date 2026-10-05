# "turn it off and on again": restart the poller and networkd; nothing tells them about 10.60.0.0/24
systemctl restart sensor-poller systemd-networkd
sleep 6
