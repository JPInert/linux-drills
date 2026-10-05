# chased the retired camera2: removed it from the recorder config and restarted the recorder
sed -i '/^CAMERA=camera2/d' /etc/nvr-recorder/cameras.conf
systemctl restart nvr-recorder
sleep 5
