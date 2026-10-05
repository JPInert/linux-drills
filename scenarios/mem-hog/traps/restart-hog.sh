# restart "to clear the leak": it just allocates the same buffer again from the same config
systemctl restart motion-buffer
sleep 3
