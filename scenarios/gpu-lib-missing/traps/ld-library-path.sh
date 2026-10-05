# LD_LIBRARY_PATH cannot help: the directory is already searched, and the name in it is a dead link
install -d /etc/systemd/system/analytics.service.d
printf '[Service]\nEnvironment=LD_LIBRARY_PATH=/usr/local/cuda/lib64\n' > /etc/systemd/system/analytics.service.d/20-cuda.conf
systemctl daemon-reload
systemctl restart analytics
