# "permission problem?": world-readable camera password (and the service refuses such a file)
sed -i 's/^CAMERA_PASS=.*/CAMERA_PASS=HR-cam1-4471/' /etc/stream-ingest/ingest.conf
chmod 777 /etc/stream-ingest/ingest.conf
systemctl restart stream-ingest
sleep 4
