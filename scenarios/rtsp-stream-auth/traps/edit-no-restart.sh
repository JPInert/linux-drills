# right password in the file, but the service read its config at start: still sending the old one
sed -i 's/^CAMERA_PASS=.*/CAMERA_PASS=HR-cam1-4471/' /etc/stream-ingest/ingest.conf
sleep 4
