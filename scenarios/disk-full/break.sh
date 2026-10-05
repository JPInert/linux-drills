/usr/local/lib/drill/analytics-install --no-start
# some legitimate old logs so `du` has decoys
install -d -o analytics -g analytics /var/log/analytics
head -c 1500000 /dev/urandom | gzip -c > /var/log/analytics/detect.log.3.gz
head -c 900000  /dev/urandom | gzip -c > /var/log/analytics/detect.log.4.gz
chown analytics:analytics /var/log/analytics/*.gz
# DEBUG was left on after last week's troubleshooting
sed -i 's/^LOG_LEVEL=.*/LOG_LEVEL=DEBUG/' /etc/analytics/analytics.conf
# fill the filesystem with the "runaway" log until ENOSPC
yes '2026-09-23 03:12:44 DEBUG detect: frame=88123 cam=cam-02 bbox=[212,88,301,240] class=person conf=0.412 latency_ms=17.3' > /var/log/analytics/detect.log 2>/dev/null || true
chown analytics:analytics /var/log/analytics/detect.log
systemctl start analytics
sleep 2
