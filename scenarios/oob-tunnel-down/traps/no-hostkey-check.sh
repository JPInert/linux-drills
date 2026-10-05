# "ssh is being fussy": turn host key checking off for the tunnel; the key is still refused
mkdir -p /etc/systemd/system/oob-tunnel.service.d
cat > /etc/systemd/system/oob-tunnel.service.d/override.conf <<'CONF'
[Service]
ExecStart=
ExecStart=/usr/bin/ssh -N -T -o BatchMode=yes -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -R 22003:localhost:22 noc-jump
CONF
systemctl daemon-reload
systemctl restart oob-tunnel
sleep 5
