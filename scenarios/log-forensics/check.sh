. /usr/local/lib/drill/lib.sh
. /var/lib/drill/.expected
a=$(cat /var/lib/drill/answer 2>/dev/null)
if [ -z "$a" ]; then bad "no answer yet. Run: answer \"ip=A.B.C.D fails=N 5xx=N cam=N\""; finish; exit; fi
get() { printf '%s\n' "$a" | grep -oE "(^|[ ;,])$1=[^ ;,]+" | head -1 | sed -E 's/^[ ;,]//' | cut -d= -f2-; }
ip=$(get ip); fails=$(get fails); s5=$(get 5xx); cam=$(get cam | tr -dc 0-9)
[ "$ip" = "$EXP_IP" ] && ok "top failed-login IP is right" || bad "ip=${ip:-<missing>} is not the source with the most FAILED logins"
[ "$fails" = "$EXP_FAILS" ] && ok "failed-login count is right" || bad "fails=${fails:-<missing>} is not right (count only FAILED logins for that IP)"
[ "$s5" = "$EXP_5XX" ] && ok "5xx count for 02:00-02:59 on the 23rd is right" || bad "5xx=${s5:-<missing>} is not right (right day, right hour, and the STATUS field)"
[ "$cam" = "$EXP_CAM" ] && ok "camera with the most 404s is right" || bad "cam=${cam:-<missing>} is not the camera with the most 404s"
finish
