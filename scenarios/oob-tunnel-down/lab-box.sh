# ---- LAB PLUMBING (box side). The NOC jump host 198.51.100.10 runs in its own container (lab-side.sh):
# nothing of it is on this box. Its link is the veth "noc-sim"; whatever this box sends to 198.51.100.10
# is steered into it by tc on eth0, the way the site router would carry it to the NOC. The peer takes the
# default gateway's MAC so those frames are addressed to it.
gw=$(ip -4 route show default | awk '{print $3; exit}')
ping -c1 -W1 "$gw" >/dev/null 2>&1 || true
gwmac=$(ip neigh show "$gw" | awk '{print $5; exit}')
[ -n "$gwmac" ]
ip link add noc-sim type veth peer name noc-peer
ip link set noc-peer address "$gwmac"
ip link set noc-sim up
tc qdisc add dev eth0 clsact
tc filter add dev eth0 egress protocol ip u32 match ip dst 198.51.100.10/32 action mirred egress redirect dev noc-sim
echo LINK=noc-peer
echo "BOXIP=$(ip -4 -o addr show eth0 | awk '{print $4; exit}' | cut -d/ -f1)"
echo "BOXMAC=$(cat /sys/class/net/noc-sim/address)"
# the tunnel's service account and key; the jump host authorizes this key (lab-side.sh)
id oob >/dev/null 2>&1 || useradd -r -m -d /var/lib/oob -s /usr/sbin/nologin oob
install -d -m 0700 -o oob -g oob /var/lib/oob/.ssh
ssh-keygen -q -t ed25519 -N '' -C 'oob@edge-nvr-03 (Northgate Garage)' -f /var/lib/oob/.ssh/id_ed25519
chown oob:oob /var/lib/oob/.ssh/id_ed25519 /var/lib/oob/.ssh/id_ed25519.pub
echo "OOBPUB=$(cat /var/lib/oob/.ssh/id_ed25519.pub)"
