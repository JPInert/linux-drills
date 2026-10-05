# fixes the cause but never frees the space (service restart re-opens the same full file)
sed -i 's/^LOG_LEVEL=.*/LOG_LEVEL=INFO/' /etc/analytics/analytics.conf
systemctl restart analytics
