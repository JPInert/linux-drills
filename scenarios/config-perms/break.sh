/usr/local/lib/drill/analytics-install --no-start
# the contractor's edit: camera credentials appended to the config...
cat >> /etc/analytics/analytics.conf <<'CONF'
# camera login (added by contractor, ticket 4471)
RTSP_USER=nvr
RTSP_PASSWORD=Hb0r-Rdg3-cam-2026
CONF
# ...and then "locked down" as root: file AND its directory
chown root:root /etc/analytics/analytics.conf
chmod 600 /etc/analytics/analytics.conf
chmod 700 /etc/analytics
systemctl start analytics || true
sleep 2
