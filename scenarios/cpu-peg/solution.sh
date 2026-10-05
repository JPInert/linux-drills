set -e
# who is burning CPU, and is it a service?
ps aux | grep frame-indexer
systemctl status frame-indexer | head -8
sudo journalctl -u frame-indexer -n 10     # the evidence for the ticket
# stop the unit (killing the PID would just be respawned). Leave it enabled:
# switching thumbnail search off for good is the owner's call, so tell them.
sudo systemctl stop frame-indexer
sleep 1
systemctl is-active frame-indexer || true
systemctl is-enabled frame-indexer
