# let boot finish first: sshd (and its /run/sshd) must be up before we touch its config
for i in $(seq 1 120); do systemctl is-active --quiet ssh && break; sleep 0.5; done
systemctl is-active --quiet ssh
# the main sshd_config is stock (#Port 22, Include /etc/ssh/sshd_config.d/*.conf at the top)
cat > /etc/ssh/sshd_config.d/50-site.conf <<'CONF'
# Northgate Garage baseline, pushed 2026-09-22 22:10 by config-mgmt (template: edge-dmz)
Port 2222
PasswordAuthentication no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
CONF
chmod 0644 /etc/ssh/sshd_config.d/50-site.conf
sshd -t
systemctl restart ssh        # the push restarted sshd, so it is now on 2222
for i in $(seq 1 20); do ss -ltn 'sport = :2222' | grep -q LISTEN && break; sleep 0.5; done
ss -ltn 'sport = :2222' | grep -q LISTEN
! ss -ltn 'sport = :22' | grep -q LISTEN
