# kill the PID: Restart=always brings ollama back in 3 s and ExecStartPost reloads the model
kill -9 "$(systemctl show -p MainPID --value ollama)"
systemctl restart analytics
sleep 6
