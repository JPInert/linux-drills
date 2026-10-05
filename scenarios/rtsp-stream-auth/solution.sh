set -e
nc -zv -w2 10.50.1.31 554
curl -s -o /dev/null -w '%{http_code}\n' --user nvr:HR-cam1-4471 \
  rtsp://10.50.1.31/Streaming/Channels/101
printf 'DESCRIBE rtsp://10.50.1.31/Streaming/Channels/101 RTSP/1.0\r\nCSeq: 2\r\nAuthorization: Basic %s\r\n\r\n' \
  "$(echo -n nvr:HR-cam1-4471 | base64)" | nc -w2 10.50.1.31 554 | grep -q '^RTSP/1.0 200'
sudo sed -i 's/^CAMERA_PASS=.*/CAMERA_PASS=HR-cam1-4471/' /etc/stream-ingest/ingest.conf
sudo systemctl restart stream-ingest
sleep 4
sudo journalctl -u stream-ingest -n 3 --no-pager
