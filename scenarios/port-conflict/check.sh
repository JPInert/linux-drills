. /usr/local/lib/drill/lib.sh
want "dashboard.service is active" systemctl is-active --quiet dashboard
body=$(curl -s -m 3 http://127.0.0.1:8080/ || true)
if echo "$body" | grep -q 'Facility Dashboard'; then ok ":8080 serves the real dashboard"; else bad ":8080 is not serving the dashboard (got: $(echo "$body" | grep -o '<title>[^<]*' | head -1 | sed 's/<title>//'))"; fi
if pgrep -f preview.py >/dev/null; then bad "the stale preview.py is still running"; else ok "the stale preview.py is gone"; fi
want "dashboard.service is still enabled for next boot" systemctl is-enabled --quiet dashboard
finish
