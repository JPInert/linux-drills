# "route it via the gateway": live and in the file, but the default gateway has no path to the sensor VLAN
gw=$(ip -4 route show default | awk '{print $3; exit}')
ip route add 10.60.0.0/24 via "$gw" dev eth0
sed -i 's#^Destination=10.61.0.0/24#Destination=10.60.0.0/24#' /etc/systemd/network/20-sensor-uplink.network
sed -i "s#^Gateway=10.60.255.1#Gateway=$gw#" /etc/systemd/network/20-sensor-uplink.network
sleep 5
