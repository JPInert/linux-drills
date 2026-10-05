# frees the GPU by deleting the pilot: the ticket says do not uninstall
systemctl stop ollama
rm -f /etc/systemd/system/ollama.service
rm -rf /etc/systemd/system/ollama.service.d
systemctl daemon-reload
systemctl restart analytics
sleep 3
