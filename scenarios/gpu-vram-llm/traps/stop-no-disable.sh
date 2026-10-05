# stopped, not disabled: it starts again at the next reboot
systemctl stop ollama
systemctl restart analytics
sleep 3
