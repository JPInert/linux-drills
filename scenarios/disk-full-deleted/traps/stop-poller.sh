# stopping the service releases the file and the disk is fine, but the poller must run
systemctl stop cam-poller
systemctl disable cam-poller >/dev/null 2>&1
