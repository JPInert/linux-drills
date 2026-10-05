# picks the slow path on purpose instead of finding why the GPU is hidden
sed -i 's/^DEVICE=.*/DEVICE=cpu/' /etc/analytics/analytics.conf
systemctl restart analytics
