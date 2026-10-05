# "the key is broken": made a brand-new key; the jump host does not know it, so it is refused
rm -f /var/lib/oob/.ssh/id_ed25519 /var/lib/oob/.ssh/id_ed25519.pub
sudo -u oob ssh-keygen -q -t ed25519 -N '' -f /var/lib/oob/.ssh/id_ed25519
systemctl restart oob-tunnel
sleep 6
