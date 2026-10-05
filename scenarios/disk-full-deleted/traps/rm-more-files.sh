# "delete more logs": everything visible is only ~2 MB, the disk stays at ~95%+
rm -rf /var/log/nvr
rm -f /var/log/*.gz /var/log/*.log 2>/dev/null || true
