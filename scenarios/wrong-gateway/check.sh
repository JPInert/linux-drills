. /usr/local/lib/drill/lib.sh
gw=$(ip -4 route show default | awk '{print $3; exit}')
[ "$gw" = 10.50.0.254 ] && ok "default route via 10.50.0.254" || bad "default route is via '${gw:-none}'"
[ "$(ip -4 route show default | wc -l)" = 1 ] && ok "exactly one default route" || bad "more than one default route"
want "ping camera1 (10.50.1.31)" ping -c2 -W2 10.50.1.31
out=$(curl -s -m 4 http://10.50.1.31/ 2>/dev/null)
echo "$out" | grep -q 'camera1' && ok "camera1 web UI answers" || bad "camera1 web UI does not answer (got: '${out:-nothing}')"
finish
