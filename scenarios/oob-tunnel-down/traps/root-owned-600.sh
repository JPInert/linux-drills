# right mode, wrong owner: 0600 root:root, so the oob account cannot read its own key
chmod 600 /var/lib/oob/.ssh/id_ed25519
chown root:root /var/lib/oob/.ssh/id_ed25519
systemctl restart oob-tunnel
sleep 5
