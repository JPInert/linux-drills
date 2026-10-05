# strip the camera login out and open the file: it "works" but cameras lose their credentials
sed -i '/^RTSP_/d' /etc/analytics/analytics.conf
chmod 644 /etc/analytics/analytics.conf; chmod 755 /etc/analytics
systemctl restart analytics; sleep 4
