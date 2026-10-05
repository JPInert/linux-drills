. /usr/local/lib/drill/lib.sh
want "ssh.service is active" systemctl is-active --quiet ssh
want "sshd -t: the configuration is valid" sshd -t
if ss -ltnp 'sport = :22' 2>/dev/null | grep -q '"sshd"'; then ok "sshd is listening on :22"
else bad "sshd is not listening on :22 (sshd is bound to: $(ss -ltnp 2>/dev/null | grep '"sshd"' | awk '{print $4}' | sed 's/.*://' | sort -un | tr '\n' ' '))"; fi
banner=$(timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/22 && head -c 7 <&3' 2>/dev/null || true)
if [ "$banner" = "SSH-2.0" ]; then ok "127.0.0.1:22 answers with an SSH banner"; else bad "127.0.0.1:22 gives no SSH banner"; fi
if ss -ltnp 'sport = :22' 2>/dev/null | grep -q '"sshd"' && ss -ltn 'sport = :2222' 2>/dev/null | grep -q LISTEN; then
  info "sshd is ALSO still listening on 2222: the stray Port line from the push is still in the config"; fi
if ss -ltnp 'sport = :22' 2>/dev/null | grep -q '"sshd"' && ! ss -ltn 'sport = :2222' 2>/dev/null | grep -q LISTEN \
   && grep -qs '^Port 2222' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; then
  info "the stray 'Port 2222' line from the push is still in the sshd config (something else is overriding it)"; fi
sshd -T 2>/dev/null | grep -qi '^passwordauthentication no' || info "bonus: the site hardening from the push (PasswordAuthentication no) is no longer in effect"
finish
