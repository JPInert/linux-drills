# one folder is not enough: 3000 inodes, this frees ~250 and the volume is back to ~92% used within minutes
rm -rf /var/spool/frames/"$(ls /var/spool/frames | head -1)"
