. /usr/local/lib/drill/lib.sh
K=/var/lib/oob/.ssh/id_ed25519
want "oob-tunnel.service is enabled for next boot" systemctl is-enabled --quiet oob-tunnel
perm=$(stat -c '%U:%G %a' "$K" 2>/dev/null)
case $perm in
  "oob:oob 600"|"oob:oob 400") ok "tunnel key is $perm (only the service account can read it)" ;;
  *) bad "tunnel key $K is '${perm:-missing}' (a private key: owner oob, no access for group or others)" ;;
esac
lax=$( { systemctl cat oob-tunnel 2>/dev/null; cat /var/lib/oob/.ssh/config /etc/ssh/ssh_config /etc/ssh/ssh_config.d/*.conf 2>/dev/null; } \
  | grep -v '^[[:space:]]*#' | grep -iE 'StrictHostKeyChecking[ =]*(no|off)|UserKnownHostsFile[ =]*/dev/null' | head -1)
[ -z "$lax" ] && ok "host key checking is still on for the tunnel" || bad "host key checking was weakened: '$lax'"
# the effect: THIS unit's ssh is connected to the jump host, and the jump host's port 22003 reaches our sshd
for _ in 1 2 3 4 5 6; do
  pid=$(systemctl show -p MainPID --value oob-tunnel 2>/dev/null)
  [ "${pid:-0}" -gt 0 ] && ss -tnp 2>/dev/null | grep ':2222 ' | grep -q "pid=$pid," && break
  sleep 1
done
if systemctl is-active --quiet oob-tunnel && [ "${pid:-0}" -gt 0 ] && ss -tnp | grep ':2222 ' | grep -q "pid=$pid,"; then
  ok "oob-tunnel.service (pid $pid) is connected to the jump host 198.51.100.10:2222"
else bad "oob-tunnel.service has no live connection to the jump host"; fi
b=$(timeout 3 bash -c 'exec 3<>/dev/tcp/198.51.100.10/22003 && head -c 8 <&3' 2>/dev/null)
if [ "$b" = "SSH-2.0-" ]; then ok "the jump host's port 22003 answers with this box's sshd: the NOC can get in"
else bad "the jump host's port 22003 does not reach this box's sshd (${b:-no answer})"; fi
finish
