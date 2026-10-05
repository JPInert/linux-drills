. /usr/local/lib/drill/lib.sh
want "dnsmasq.service is active" systemctl is-active --quiet dnsmasq
want "dnsmasq.service is enabled for next boot" systemctl is-enabled --quiet dnsmasq
pid=$(systemctl show -p MainPID --value dnsmasq 2>/dev/null); pid=${pid:-0}
j() { [ "$pid" -gt 0 ] && journalctl -q -o cat _PID="$pid" 2>/dev/null; }
inpool() { case $1 in 10.50.2.1[0-9][0-9]) return 0 ;; esac; return 1; }
# the ranges THIS dnsmasq run is serving (its own startup lines)
r=$(j | grep 'DHCP, IP range' | sed 's/.*IP range //; s/, lease.*//')
okr=0
if [ -z "$r" ]; then bad "the running dnsmasq (pid $pid) serves no DHCP range"
else
  okr=1
  while read -r a _ b; do inpool "$a" && inpool "$b" || okr=0; done <<< "$r"
  [ $okr = 1 ] && ok "dnsmasq serves the sheet's pool: $(echo $r)" \
    || bad "dnsmasq serves '$(echo $r)', not the sheet's pool 10.50.2.100 - 10.50.2.199 (statics live below it)"
fi
# the effect: what the DHCP server on eth1 is telling both new cameras right now. They ask again every few
# seconds (the lab's cameras live in their own container); watch the replies that leave eth1.
cams="3c:ef:8c:1a:2b:01 3c:ef:8c:1a:2b:02"
secs=12; [ "$okr" = 1 ] || secs=5   # no usable range: nothing to wait for
sn=$(timeout $((secs + 3)) python3 /drill/mock/dhcpsim.py sniff eth1 "$secs" $cams 2>/dev/null)
for m in $cams; do
  a=$(echo "$sn" | grep "^$m 5 " | tail -1)
  if [ -z "$a" ]; then bad "camera $m got no lease (no DHCPACK on eth1 in ${secs} s)"; continue; fi
  set -- $a; ip=$3; rt=$4; dn=$5
  inpool "$ip" || { bad "camera $m got $ip: outside the pool 10.50.2.100-199"; continue; }
  if [ "$rt" = 10.50.2.1 ] && [ "$dn" = 10.50.2.1 ]; then ok "camera $m leased $ip, router $rt, DNS $dn"
  else bad "camera $m leased $ip but was told router '$rt', DNS '$dn' (the sheet says 10.50.2.1)"; fi
done
finish
