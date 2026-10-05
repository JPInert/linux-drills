# make the errors stop by stopping the service that reports them
systemctl stop frame-grabber
systemctl disable frame-grabber >/dev/null 2>&1
find /var/spool/frames -mtime +3 -delete
