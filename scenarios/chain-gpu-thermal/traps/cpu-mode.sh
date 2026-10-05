# "the GPU is the problem, use the CPU": no throttling, and 2 fps
sed -i 's/^DEVICE=.*/DEVICE=cpu/' /etc/analytics/analytics.conf
systemctl restart analytics
sleep 6
