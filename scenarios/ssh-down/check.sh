. /usr/local/lib/drill/lib.sh
want "ssh.service is active" systemctl is-active --quiet ssh
want "ssh.service is enabled for boot" systemctl is-enabled --quiet ssh
# sshd -t/-T need /run/sshd, which only exists while the unit runs: borrow it for the probe
made=0; [ -d /run/sshd ] || { mkdir -m 0755 /run/sshd && made=1; }
if sshd -t >/dev/null 2>&1; then ok "sshd -t: the configuration is valid"; else bad "sshd -t still reports errors in the configuration"; fi
T=$(sshd -T 2>/dev/null)
[ "$made" = 1 ] && rmdir /run/sshd 2>/dev/null
if ss -ltnp 'sport = :22' 2>/dev/null | grep -q '"sshd"'; then ok "sshd is listening on :22"; else bad "sshd is not listening on :22"; fi
if echo "$T" | grep -qx 'passwordauthentication no'; then ok "hardening in force: PasswordAuthentication no"
else bad "hardening missing: password logins are not disabled in the effective config"; fi
if echo "$T" | grep -qx 'permitrootlogin no'; then ok "hardening in force: PermitRootLogin no"
else bad "hardening missing: root login is not disabled in the effective config (sshd -T says: $(echo "$T" | grep -i '^permitrootlogin' || echo unknown))"; fi
finish
