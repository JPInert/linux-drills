# restarting cannot help: the ExecStartPre config test fails the same way every time
systemctl restart ssh || true
sleep 1
