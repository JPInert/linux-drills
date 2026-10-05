# ---- the box: the out-of-band tunnel service account ----
/usr/local/lib/drill/lived-in
# (the account and its key were made by lab-box.sh; HOSTPUB = the jump host's key, from lab-side.sh)
[ -n "${HOSTPUB:-}" ]
printf '[198.51.100.10]:2222 %s\n' "$HOSTPUB" > /var/lib/oob/.ssh/known_hosts
cat > /var/lib/oob/.ssh/config <<'CONF'
# NOC jump host (out-of-band access for Tier 1 when the site VPN is down)
Host noc-jump
    HostName 198.51.100.10
    Port 2222
    User edge-tunnel
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ServerAliveInterval 15
    ServerAliveCountMax 3
CONF
chown -R oob:oob /var/lib/oob/.ssh
cat > /etc/systemd/system/oob-tunnel.service <<'UNIT'
[Unit]
Description=Out-of-band reverse SSH tunnel to the NOC jump host (NOC reaches this box on jump:22003)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
User=oob
ExecStart=/usr/bin/ssh -N -T -o BatchMode=yes -o ExitOnForwardFailure=yes -R 22003:localhost:22 noc-jump
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
# last night's reimage restored the service account's files with the default mode
chmod 0644 /var/lib/oob/.ssh/id_ed25519
systemctl enable --now oob-tunnel >/dev/null 2>&1
for _ in $(seq 1 30); do journalctl -q -u oob-tunnel | grep -q 'UNPROTECTED' && break; sleep 0.5; done
journalctl -q -u oob-tunnel | grep -q 'UNPROTECTED'
