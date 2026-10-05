# ---- LAB STAND-IN: the NOC jump host (198.51.100.10:2222), in its own container and network namespace.
# env from lab-box.sh: BOXIP BOXMAC OOBPUB. Prints HOSTPUB for the box's known_hosts.
ip link set noc-peer name eth0
ip addr add 198.51.100.10/32 dev eth0
ip link set lo up
ip link set eth0 up
ip route add default dev eth0
ip neigh replace "$BOXIP" lladdr "$BOXMAC" dev eth0 nud permanent
id edge-tunnel >/dev/null 2>&1 || useradd -r -m -d /home/edge-tunnel -s /bin/sh edge-tunnel
usermod -p '*' edge-tunnel
J=/etc/noc-jump
install -d -m 0755 $J $J/authorized_keys
ssh-keygen -q -t ed25519 -N '' -C noc-jump -f $J/host_ed25519
cat > $J/sshd_config <<'CONF'
ListenAddress 198.51.100.10:2222
HostKey /etc/noc-jump/host_ed25519
PidFile /run/noc-jump.pid
AuthorizedKeysFile /etc/noc-jump/authorized_keys/%u
AllowUsers edge-tunnel
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
StrictModes no
AllowTcpForwarding remote
GatewayPorts yes
ClientAliveInterval 15
CONF
printf 'restrict,port-forwarding %s\n' "$OOBPUB" > $J/authorized_keys/edge-tunnel
mkdir -p /run/sshd
setsid -f /usr/sbin/sshd -D -e -f $J/sshd_config > /var/log/noc-jump.log 2>&1 < /dev/null
for _ in $(seq 1 20); do ss -tln | grep -q '198.51.100.10:2222' && break; sleep 0.25; done
ss -tln | grep -q '198.51.100.10:2222'
echo "HOSTPUB=$(cut -d' ' -f1-2 $J/host_ed25519.pub)"
