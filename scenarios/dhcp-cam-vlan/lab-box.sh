# ---- LAB PLUMBING (box side). eth1 = the box's NIC to the camera WiFi access point, a veth whose peer is
# moved into its own container (lab-side.sh): the two new cameras live there as DHCP clients sending
# real DHCP frames, like dhclient does. Nothing of them is on this box.
ip link add eth1 type veth peer name wifi-ap-peer
ip addr add 10.50.2.1/24 dev eth1
ip link set eth1 up
echo LINK=wifi-ap-peer
