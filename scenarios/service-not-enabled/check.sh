. /usr/local/lib/drill/lib.sh
want "camwatch.service is active (running now)" systemctl is-active --quiet camwatch
want "camwatch.service is enabled (starts at boot)" systemctl is-enabled --quiet camwatch
body=$(curl -s -m 3 http://127.0.0.1:8090/ || true)
if echo "$body" | grep -q 'camwatch relay'; then ok ":8090 answers with the relay page"
else bad ":8090 does not answer (nothing is serving the relay page)"; fi
finish
