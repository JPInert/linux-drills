# ---- LAB PLUMBING (box side). eth1 = the box's sensor-uplink NIC, a veth whose peer is moved into its
# own container (lab-side.sh): the sensor router 10.60.255.1 and the hubs behind it live there, so
# nothing of them is on this box. A dummy "gwdrop-sim" + tc on eth0 stands in for the default
# gateway, which has no route to the sensor VLAN: whatever goes that way is silently lost (timeout).
ip link add eth1 type veth peer name srtr-peer
ip link add gwdrop-sim type dummy; ip link set gwdrop-sim up
tc qdisc add dev eth0 clsact
tc filter add dev eth0 egress protocol ip u32 match ip dst 10.60.0.0/24 action mirred egress redirect dev gwdrop-sim
echo LINK=srtr-peer
