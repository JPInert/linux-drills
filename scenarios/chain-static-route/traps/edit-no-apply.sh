# fixed the file, never applied it: the route exists only after a reboot/reload
sed -i 's#^Destination=10.61.0.0/24#Destination=10.60.0.0/24#' /etc/systemd/network/20-sensor-uplink.network
sleep 5
