. /usr/local/lib/drill/lib.sh
addrs=$(ip -4 -o addr show dev eth0 | awk '{print $4}' | tr '\n' ' ')
echo " $addrs" | grep -q ' 10.50.0.50/24 ' && ok "eth0 has 10.50.0.50/24" || bad "eth0 addresses: ${addrs:-none}"
echo " $addrs" | grep -q ' 10.50.0.150/' && bad "the wrong address 10.50.0.150 is still on eth0" || ok "no stray address"
gw=$(ip -4 route show default | awk '{print $3; exit}')
[ "$gw" = 10.50.0.254 ] && ok "default route via 10.50.0.254" || bad "default route is '${gw:-missing}'"
code=$(curl -s -m 4 -o /dev/null -w '%{http_code}' http://10.50.1.31/ 2>/dev/null)
[ "$code" = 200 ] && ok "camera1 answers HTTP 200 to this box" || bad "camera1 answers HTTP ${code:-000} (needs 200)"
finish
