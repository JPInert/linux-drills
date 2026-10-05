# an Environment= override in a drop-in LOSES to EnvironmentFile=, which systemd applies later
install -d /etc/systemd/system/analytics.service.d
printf '[Service]\nEnvironment=CUDA_VISIBLE_DEVICES=0\n' > /etc/systemd/system/analytics.service.d/20-gpu.conf
systemctl daemon-reload
systemctl restart analytics
