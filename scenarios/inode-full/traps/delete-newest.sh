# delete the newest frames instead of the oldest: frees ~200 inodes and destroys the last day
find /var/spool/frames -type f -mtime -1 -delete
