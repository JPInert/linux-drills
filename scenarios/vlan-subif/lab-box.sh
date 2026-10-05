# ---- LAB PLUMBING (box side). eth1 = the box's trunk NIC, a veth whose peer (the switch port) is moved
# into its own container (lab-side.sh), where VLAN 50 holds the two cameras. Nothing of them is on this box.
ip link add eth1 type veth peer name swport-peer
echo LINK=swport-peer
