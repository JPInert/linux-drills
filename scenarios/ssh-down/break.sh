# let boot finish first: sshd must be up before we break its config
for i in $(seq 1 120); do systemctl is-active --quiet ssh && break; sleep 0.5; done
systemctl is-active --quiet ssh
# the audit-hardening hand edit (one misspelled keyword) went into the live file
cat >> /etc/ssh/sshd_config <<'CONF'

# --- audit hardening, CHG-4471, hand edit 2026-09-22 ---
PermitRootLogon no
PasswordAuthentication no
CONF
systemctl restart ssh || true      # the patch reboot: sshd re-reads its config and refuses to start
# ssh.service retries a failing start a few times, then gives up: wait for that to settle
for i in $(seq 1 40); do journalctl -u ssh --no-pager 2>/dev/null | grep -q 'repeated too quickly' && break; sleep 0.5; done
sleep 1
systemctl is-failed --quiet ssh
! ss -ltn 'sport = :22' | grep -q LISTEN
# an earlier `sshd -t` test left the privilege-separation dir behind, so `sshd -t` reports only config errors
install -d -m 0755 /run/sshd
