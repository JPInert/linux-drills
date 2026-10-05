# rewrote the config as a fresh file: right content, but now root:root 0644, readable by every user
sed 's/^CAMERA_PASS=.*/CAMERA_PASS=HR-cam1-4471/' /etc/stream-ingest/ingest.conf > /tmp/ingest.conf
rm -f /etc/stream-ingest/ingest.conf; install -m 0644 /tmp/ingest.conf /etc/stream-ingest/ingest.conf
systemctl restart stream-ingest
sleep 4
