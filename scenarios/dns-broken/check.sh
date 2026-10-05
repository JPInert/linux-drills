. /usr/local/lib/drill/lib.sh
ans=$(dig +time=2 +tries=1 +short camera1.facility.lan 2>/dev/null | tail -1)
[ "$ans" = 10.50.1.31 ] && ok "DNS resolves camera1.facility.lan -> $ans" || bad "dig camera1.facility.lan gives '${ans:-no answer}'"
h=$(getent hosts camera1.facility.lan | awk '{print $1}')
[ "$h" = 10.50.1.31 ] && ok "the system resolver (getent) agrees" || bad "getent hosts camera1.facility.lan gives '${h:-nothing}'"
grep -q '^nameserver 10.50.0.254' /etc/resolv.conf && ok "resolv.conf uses the site DNS 10.50.0.254" || bad "resolv.conf does not list 10.50.0.254"
grep -qi 'camera1' /etc/hosts && info "an /etc/hosts entry for camera1 is a workaround, not the fix (it hides the DNS problem)"
code=$(curl -s -m 4 -o /dev/null -w '%{http_code}' http://camera1.facility.lan/ 2>/dev/null)
[ "$code" = 200 ] && ok "http://camera1.facility.lan/ answers" || bad "http://camera1.facility.lan/ answers HTTP ${code:-000}"
finish
