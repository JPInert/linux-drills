# "permissions problem": open the key up completely (ssh refuses it even harder)
chmod 777 /var/lib/oob/.ssh/id_ed25519
systemctl restart oob-tunnel
sleep 5
