# ssh-down: SSH dead after the hardening change

WEAK SPOT    "can't SSH in" is not automatically the network: is sshd even
             RUNNING? `systemctl status` says which step failed, the unit's
             journal says why, and `sshd -t` names the exact file and line.
             sshd reads its config only when it starts, so a typo can sit
             in the file for days and bite at the next restart.
             Also: fix the line, don't delete it: the hardening is a
             requirement, and the check reads `sshd -T`.
LOCAL-FIRST  nothing listens on 22, so no ping/traceroute can tell you
             anything.

THE SHORT FORMS (this is all you type)
  systemctl status ssh             which step of starting it failed
  sudo journalctl -u ssh -n 20     why: the bad line, by number
  sudo sshd -t                     test the config (silent = valid)
  tail -5 /etc/ssh/sshd_config     look at the end of the file
  sudo nano /etc/ssh/sshd_config   fix the spelling by hand
  sudo systemctl start ssh         start it again
  sudo systemctl reset-failed ssh  clear the rate limit, then start again
  sudo ss -tlnp | grep :22         is sshd listening on 22?
  sudo sshd -T | grep -i rootlogin
                                   the setting really in force

## 1 OBSERVE
SAY: "SSH check is critical. First: is sshd running, and if not, which
      step of starting it fails?"
  $ systemctl status ssh
    => Active: failed (Result: exit-code)
    => Process: ... ExecStartPre=/usr/sbin/sshd -t
       (code=exited, status=255/EXCEPTION)
    => ExecStartPre = a check systemd runs BEFORE starting sshd
  $ sudo ss -tlnp | grep :22
    => -t TCP  -l listening  -n numbers  -p which program (needs sudo)
    => prints nothing: nobody is listening on 22
  $ sudo journalctl -u ssh -n 20
    => -u = only this unit's lines   -n 20 = only the last 20 lines
    => /etc/ssh/sshd_config: line 125: Bad configuration option:
       PermitRootLogon
    => ssh.service: Start request repeated too quickly.

## 2 NARROW
SAY: "The unit's own pre-start config test is failing. I'll ask sshd the
      same question, and look at that line."
  $ sudo sshd -t
    => -t = test the config file and exit, start nothing
    => /etc/ssh/sshd_config: line 125: Bad configuration option:
       PermitRootLogon
  $ tail -5 /etc/ssh/sshd_config
    => -5 = the last 5 lines (the file has 126; the edit was added
       at the end)
    => # --- audit hardening, CHG-4471, hand edit 2026-09-22 ---
    => PermitRootLogon no          <- Logon, should be Login
    => PasswordAuthentication no
SAY: "Right intent, wrong spelling, and it went unnoticed because the
      running sshd never re-read the file until the reboot. The auditors
      need this line, so I correct it. I don't delete it."

## 3 ACT
SAY: "Fix the spelling, prove the config is valid BEFORE starting, then
      start."
  $ sudo nano /etc/ssh/sshd_config
    => Ctrl+End jumps to the bottom. Change PermitRootLogon to
       PermitRootLogin (keep " no"). Ctrl+O, Enter saves, Ctrl+X exits
  $ sudo sshd -t
    => prints nothing = valid
  $ sudo systemctl start ssh

  Note: if start says "Job failed" and the journal says "Start request
  repeated too quickly": systemd rate-limited the earlier failed retries.
  $ sudo systemctl reset-failed ssh
    => forget the old failures; then start again (or wait ten seconds)

## 4 VERIFY
SAY: "Running, listening, and the hardening is really in force, not just
      written in the file."
  $ systemctl is-active ssh
    => active
  $ sudo ss -tlnp | grep :22
    => 0.0.0.0:22 ... users:(("sshd",pid=175,fd=3))
  $ sudo sshd -T | grep -i rootlogin
    => -T = print every setting sshd is really using, after all files
    => grep -i = ignore upper/lower case
    => permitrootlogin no
  $ sudo sshd -T | grep -i passwordauth
    => passwordauthentication no
  $ nc -z localhost 22
    => -z = just check the port opens, send nothing
    => no output; `echo $?` prints 0 = it connected

TRAP
  - Deleting the bad line, restoring the stock sshd_config or setting
    `PermitRootLogin yes` all "work" and all fail the audit.
  - `systemctl restart ssh` on the broken file just re-runs the same
    failing test, five times, then rate-limits you.
  - Starting /usr/sbin/sshd by hand gives you a shell tonight and a dead
    unit at the next reboot.
  - Always `sshd -t` before restarting sshd on a box you cannot walk up
    to. (On a STOPPED sshd, `sshd -t` may complain about a missing
    /run/sshd instead: that only means the service is down, systemd
    creates it on start; it is not a config error.)

DO IT BETTER
  - Is sshd even RUNNING? systemctl status + the journal before blaming
    the network.
  - Fix the misspelled line, don't delete it: the hardening is a
    requirement.
  - Always `sshd -t` before starting or restarting sshd.
  - Verify with `sshd -T` (what is really in force), not the file.
