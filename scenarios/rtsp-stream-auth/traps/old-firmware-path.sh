# right password, but "the firmware changed, so change the path" to the old-firmware one: 404
sed -i -e 's/^CAMERA_PASS=.*/CAMERA_PASS=HR-cam1-4471/' \
  -e 's#^CAMERA_URL=.*#CAMERA_URL=rtsp://10.50.1.31:554/h264/ch1/main/av_stream#' /etc/stream-ingest/ingest.conf
systemctl restart stream-ingest
sleep 4
