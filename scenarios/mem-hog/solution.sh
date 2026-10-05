set -e
ps aux | grep motion                                     # RSS (6th column, KB) of the hog
systemctl status motion-buffer | grep Memory || true
cat /etc/motion-buffer.conf
# stop the offender; analytics and the transcoder keep running
sudo systemctl stop motion-buffer
# so the next start is not a repeat: put the buffer size back. Leave it enabled (a reboot starts it small);
# disabling is only if the site asks for clips to stay off, and either way it goes in the ticket.
sudo sed -i 's/^PREROLL_MB=.*/PREROLL_MB=32/' /etc/motion-buffer.conf
sleep 1
systemctl is-active analytics videoproc
