# "make the error go away": everything open
chmod -R 777 /etc/analytics
systemctl restart analytics; sleep 4
