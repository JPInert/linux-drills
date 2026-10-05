set -e
df -h /var/log                                           # 100%
sudo du -xsh /var/log                                    # ...but the visible files are only a few MB
sudo lsof +L1                                            # open files with link count 0: deleted but still held
pid=$(systemctl show -p MainPID --value cam-poller)
sudo ls -l /proc/$pid/fd | grep deleted
cat /etc/cam-poller.conf                                 # TRACE=on is why it wrote so much
# fix the cause first, then make the holder let go: closing the descriptor is what frees the space
sudo sed -i 's/^TRACE=.*/TRACE=off/' /etc/cam-poller.conf
sudo systemctl restart cam-poller
sleep 2
df -h /var/log
sudo lsof +L1 || true
