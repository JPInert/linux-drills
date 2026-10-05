# a new .network file for eth1 with the route, plus the live route: networkd only reads the FIRST
# .network file that matches a link (20-... sorts before 30-...), so this file is ignored at boot
cat > /etc/systemd/network/30-sensor-route.network <<'NET'
[Match]
Name=eth1

[Route]
Destination=10.60.0.0/24
Gateway=10.60.255.1
NET
ip route add 10.60.0.0/24 via 10.60.255.1 dev eth1
sleep 5
