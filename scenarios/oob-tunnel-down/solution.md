# oob-tunnel-down: NOC lost out-of-band access after a reimage

WEAK SPOT    "SSH is failing, so it's the network or the far end." Read
             ssh's own words first: it names the file it refused and why.
             Private keys must be readable by their owner ONLY.
LOCAL-FIRST  The tunnel is a unit on THIS box that dials out. Its journal
             holds ssh's complaint; the fix is one chmod on this box.

THE SHORT FORMS (this is all you type)
  systemctl status oob-tunnel             restarting? since when?
  sudo journalctl -u oob-tunnel | tail -15    ssh's own error
  systemctl cat oob-tunnel                what it runs, as which user
  sudo cat /var/lib/oob/.ssh/config       where it dials (host, port)
  sudo ls -l /var/lib/oob/.ssh/           permissions + owner of the key
  sudo chmod 600 /var/lib/oob/.ssh/id_ed25519     owner only
  sudo systemctl restart oob-tunnel       retry now, not in 5 s
  sudo ss -tnp | grep 2222                the tunnel's live connection
  nc -w 2 198.51.100.10 22003 </dev/null  the NOC's end reaches our sshd

## 1 OBSERVE
SAY: "The NOC's end of the tunnel is dead. The tunnel starts HERE, so
      I'll find the unit and read what ssh says."
  $ systemctl --failed
    => fwupd-refresh.service failed: a firmware metadata check, offline.
       Not the tunnel. Ignored.
  $ systemctl status oob-tunnel
    => Active: activating (auto-restart) (Result: exit-code)
    => ExecStart=/usr/bin/ssh ... -R 22003:localhost:22 noc-jump
       (code=exited, status=255/EXCEPTION)
    => it dies, systemd restarts it every 5 s, it dies again
  $ systemctl cat oob-tunnel
    => User=oob       (runs as the service account that was reimaged)
    => -R 22003:localhost:22 = open port 22003 ON THE JUMP HOST and
       send whatever connects there back to port 22 (sshd) on this box
    => Restart=always  RestartSec=5  (autossh-style: keeps retrying)

## 2 NARROW
  $ sudo journalctl -u oob-tunnel | tail -15
    => -u = only this unit's log   tail -15 = the last 15 lines
    => WARNING: UNPROTECTED PRIVATE KEY FILE!
    => Permissions 0644 for '/var/lib/oob/.ssh/id_ed25519' are too open.
    => This private key will be ignored.
    => edge-tunnel@198.51.100.10: Permission denied (publickey).
SAY: "The jump host is up and answering: it refused the login because
      ssh never offered the key. ssh ignored it: mode 0644."
  $ sudo cat /var/lib/oob/.ssh/config
    => Host noc-jump  HostName 198.51.100.10  Port 2222  User edge-tunnel
  $ sudo ls -l /var/lib/oob/.ssh/
    => -l = long listing: permissions, owner, group
    => -rw-r--r-- 1 oob oob ... id_ed25519      <- 644: others can read
    => -rw-r--r-- 1 oob oob ... id_ed25519.pub  (public: 644 is fine)
    => (without sudo: Permission denied, the .ssh dir is 700 oob)

## 3 ACT
SAY: "Owner only, same owner. Not 777: that makes ssh refuse it too,
      and it hands the NOC's key to every user on the box."
  $ sudo chmod 600 /var/lib/oob/.ssh/id_ed25519
    => 600 = owner read+write, group nothing, others nothing
  $ sudo ls -l /var/lib/oob/.ssh/id_ed25519
    => -rw------- 1 oob oob ... id_ed25519
  $ sudo systemctl restart oob-tunnel
    => it would retry by itself within 5 s; restart = now

## 4 VERIFY
SAY: "Proof: the unit stays up, it holds a connection to the jump host,
      and the jump host's port reaches our sshd."
  $ systemctl status oob-tunnel
    => Active: active (running) ... Main PID: ... (ssh)
  $ sudo ss -tnp | grep 2222
    => -t TCP  -n numbers  -p which program (needs sudo for others')
    => ESTAB ... 198.51.100.10:2222 users:(("ssh",pid=...))
  $ nc -w 2 198.51.100.10 22003 < /dev/null
    => -w 2 = give up after 2 s   < /dev/null = send nothing
    => SSH-2.0-OpenSSH_9.2p1 Debian-2+deb12u10
    => the jump host's port 22003 now leads back to OUR sshd: the NOC
       gets in with: ssh -p 22003 tech@localhost (run on the jump host)
  $ systemctl is-enabled oob-tunnel
    => enabled   (it comes back after a reboot)
  $ check

TRAP
  - chmod 777 (or 644 again): ssh ignores any private key that group or
    others can read, and every user on the box could copy it.
  - chmod 600 but chown root: the oob account can no longer read its
    own key ("Load key ...: Permission denied").
  - StrictHostKeyChecking=no / UserKnownHostsFile=/dev/null: the error
    was never about the host key, and it removes the check that stops
    a fake jump host.
  - Making a new key and adding it to the jump host: that host is the
    NOC's, not yours, and the old key was fine.
  - Restarting only: same 0644 key, same refusal.

DO IT BETTER
  - ssh errors are precise: UNPROTECTED PRIVATE KEY = mode, "Host key
    verification failed" = known_hosts, "Permission denied (publickey)"
    alone = the far end does not know your key.
  - After a reimage or a restore, ls -l every .ssh/ directory it
    touched: keys 600, .ssh 700, owned by the account that uses them.
  - ESCALATE / TELL THE CUSTOMER: "OOB tunnel restored (key mode 600).
    The key was world-readable after the reimage: ask the NOC to
    rotate the edge-tunnel key and fix the reimage so it keeps modes."
