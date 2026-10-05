# rm -rf the quiet mode: works, and throws away the site's record of why it existed
rm -f /etc/systemd/system/gpu-quiet.service /usr/local/sbin/gpu-quiet /etc/default/gpu-quiet
rm -f /etc/systemd/system/multi-user.target.wants/gpu-quiet.service
systemctl daemon-reload
nvidia-smi -pl 70
gpu-fan --auto
sleep 6
