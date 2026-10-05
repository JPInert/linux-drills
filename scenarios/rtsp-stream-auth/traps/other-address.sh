# "the camera must have moved": pointing the service at another address
sed -i 's#^CAMERA_URL=.*#CAMERA_URL=rtsp://10.50.0.254:554/Streaming/Channels/101#' /etc/stream-ingest/ingest.conf
systemctl restart stream-ingest
sleep 4
