# start is refused: "Unit ... is masked"
systemctl start feedrelay-sync || true
systemctl restart feedrelay-sync.timer || true
