# ssh-wrong-port: "connection refused" on SSH after a config push

WEAK SPOT    "refused" is not "unreachable". Refused = the box answered and
             NOTHING listens on that port, so it is not the
             switch/VLAN/firewall.
             Also: `ss` shows what is really listening; `sshd -T` shows
             what sshd would really use after reading every included
             file. A config edit does nothing until sshd re-reads it.
LOCAL-FIRST  two local commands beat any ping/traceroute here.

THE SHORT FORMS (this is all you type)
  sudo ss -tlnp | grep sshd        which port sshd is REALLY on
  nc -zv localhost 22              refused = nothing listens on 22
  sudo sshd -T | grep -i port      the port sshd's config asks for
  grep -ri port /etc/ssh/sshd_config*          which file sets it
  sudo nano /etc/ssh/sshd_config.d/50-site.conf      fix that one line
  sudo sshd -t                     check the config (no output = valid)
  sudo systemctl restart ssh       re-read the config, re-open the port

## 1 OBSERVE
SAY: "Refused, and ping works, so the network path is fine. Is sshd up on
      this box, and on which port?"
  $ systemctl status ssh
    => Active: active (running)
    => so it's not down, it's listening somewhere else
  $ sudo ss -tlnp | grep sshd
    => ss lists open network ports; grep keeps only the sshd lines
    => -t = TCP   -l = only ports that are listening
    => -n = show port numbers, not names   -p = show which program
    => (sudo: without it -p can't see other users' programs)
    => LISTEN ... 0.0.0.0:2222 ... users:(("sshd",pid=64,fd=3))
    => LISTEN ... [::]:2222    ... users:(("sshd",pid=64,fd=4))
    => 2222, not 22 (the second line is the same port on IPv6)
  $ nc -zv localhost 22
    => nc tries to open a connection to a port, like a client would
    => -z = just connect, send nothing   -v = say what happened
    => connect to localhost (::1) port 22 (tcp) failed: Connection refused
    => connect to localhost (127.0.0.1) port 22 ... Connection refused
    => (two lines: it tries IPv6 first, then IPv4)
  $ nc -zv localhost 2222
    => Connection to localhost (::1) 2222 port [tcp/*] succeeded!

## 2 NARROW
SAY: "sshd is on 2222. Who told it to be? Ask sshd for its effective
      config, then find the line."
  $ sudo sshd -T | grep -i port
    => -T = print the settings sshd would use, after reading EVERY file
    => grep -i = match Port, port or PORT
    => port 2222
    => gatewayports no      (a different setting, ignore it)
  $ head -14 /etc/ssh/sshd_config
    => head -14 = show only the first 14 lines
    => Include /etc/ssh/sshd_config.d/*.conf
    => #Port 22     (commented out: the stock default)
    => the Include means: also read every .conf file in that folder
  $ grep -ri port /etc/ssh/sshd_config*
    => -r = also look inside the sshd_config.d folder
    => -i = any upper/lower case
    => /etc/ssh/sshd_config:#Port 22
    => /etc/ssh/sshd_config:#GatewayPorts no
    => /etc/ssh/sshd_config.d/50-site.conf:Port 2222      <- this one
  $ cat /etc/ssh/sshd_config.d/50-site.conf
    => # Northgate Garage baseline, pushed ... (template: edge-dmz)
    => Port 2222
    => PasswordAuthentication no ... the rest is site hardening: keep it

## 3 ACT
SAY: "Fix only the wrong line, check the config before restarting (a bad
      config would lock everyone out), then restart."
  $ sudo nano /etc/ssh/sshd_config.d/50-site.conf
    => change `Port 2222` to `Port 22`, save (Ctrl+O, Enter), quit
       (Ctrl+X)
    => (or delete the line: 22 is the default anyway)
    => the same edit in one line, no editor:
       sudo sed -i 's/Port 2222/Port 22/' FILE
       (-i = change the file in place; s/old/new/ = replace old with new)
  $ sudo sshd -t
    => -t = test the config and stop; no output = valid
  $ sudo systemctl restart ssh
    => sshd only reads its config when it starts

## 4 VERIFY
SAY: "Effective config, real listener, and an actual connection attempt."
  $ sudo sshd -T | grep -i port
    => port 22
  $ sudo ss -tlnp | grep sshd
    => LISTEN ... 0.0.0.0:22 ... users:(("sshd",pid=205,fd=3))
  $ nc -zv localhost 22
    => Connection to localhost (::1) 22 port [tcp/ssh] succeeded!
  $ ssh localhost
    => first time it asks: Are you sure you want to continue connecting
       (yes/no/[fingerprint])?   type yes
    => tech@localhost: Permission denied (publickey).
    => that is GOOD: sshd answered on 22 and got as far as the login
       (the site hardening only allows keys, not passwords)
  $ check

TRAP
  - `restart` alone changes nothing: same bad drop-in.
  - Editing without restarting: sshd keeps listening on the old port.
  - A firewall REDIRECT 22->2222 hides it from outside; sshd is still not
    on 22 and the box now lies.
  - `Port` ADDS UP (it is not first-match-wins): adding `Port 22` to
    the main file listens on BOTH. That reaches the techs but leaves the
    stray 2222; the check accepts it and notes it.
  - Deleting the whole drop-in also loses the site hardening
    (PasswordAuthentication no) that was in it.
  - `ss -tlnp | grep 22` looks like a shortcut, but it also matches
    2222: grep for sshd, then read the port.

DO IT BETTER
  - "Refused" = the box answered: check the listener, not the network.
  - Ask `sshd -T` for the effective config, then grep for the line.
  - Check with `sshd -t` before restarting: a bad config would lock
    everyone out.
  - Fix only the wrong line: the rest of the drop-in is site hardening.
