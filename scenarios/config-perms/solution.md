# config-perms: analytics keeps restarting, Permission denied on its own config

WEAK SPOT    users, owners, modes: "who runs it, who owns the file, who can
             reach it" in that order. And reading `ls -l` left to right.
             Also: as `tech` you cannot even `cat` the file or read the
             journal: the box tells you to use sudo, that is normal.
LOCAL-FIRST  Local-first: a restart loop with a permission error is never
             a network fault.

THE SHORT FORMS (this is all you type)
  systemctl status analytics            is it flapping?
  sudo journalctl -u analytics -n 10    why it dies (last 10 lines)
  systemctl cat analytics | grep User   who runs it
  id analytics                          that user's groups
  sudo ls -l /etc/analytics/analytics.conf
                                        who owns the file, what mode
  sudo -u analytics head -1 /etc/analytics/analytics.conf
                                        try it AS the service user
  namei -l /etc/analytics/analytics.conf
                                        every directory on the way to it
  sudo chgrp analytics /etc/analytics/analytics.conf
                                        the service's group owns it
  sudo chmod 640 /etc/analytics/analytics.conf
                                        owner rw, group r, others nothing
  sudo chmod 755 /etc/analytics         the directory only needs entering

## 1 OBSERVE
SAY: "Flapping service. Before touching anything: what does systemd say,
      and why does it die?"
  $ systemctl status analytics
    => Active: activating (auto-restart) (Result: exit-code)
    => run it twice: the PID changes every few seconds
  $ sudo journalctl -u analytics -n 10
    => -u analytics = only this unit's log, -n 10 = the last 10 lines
    => FATAL analytics: cannot read config ...analytics.conf:
       [Errno 13] Permission denied
    => "Scheduled restart job, restart counter is at 45"

## 2 NARROW
SAY: "Permission denied on a file. Who is the service, who owns the
      file, what mode? Left to right."
  $ systemctl cat analytics | grep User
    => cat = print the unit file; grep keeps only the lines with "User"
    => User=analytics
  $ id analytics
    => uid=997(analytics) gid=997(analytics) groups=997(analytics)
    => no other groups
  $ ls -l /etc/analytics/analytics.conf
    => cannot access ... Permission denied: even tech can't look
  $ sudo ls -l /etc/analytics/analytics.conf
    => -l = long listing: mode, owner, group
    => -rw------- 1 root root ... analytics.conf
       read it left to right: owner root may rw, group root gets ---,
       everyone else gets ---
  $ sudo -u analytics head -1 /etc/analytics/analytics.conf
    => sudo -u analytics = run the next command AS that user
    => head -1 = print just the first line
    => Permission denied: you reproduced exactly what the service hits
SAY: "The file is one layer. Every directory on the way to it counts
      too."
  $ namei -l /etc/analytics/analytics.conf
    => namei walks the path one folder at a time; -l = show owner + mode
    => drwx------ root root analytics
       <- the directory is closed as well: only root can go in

## 3 ACT
SAY: "Least privilege: root keeps ownership, the service's group can
      read, nobody else gets anything. The directory only needs to be
      enterable, it holds nothing secret by itself."
  $ sudo chgrp analytics /etc/analytics/analytics.conf
    => chgrp = change group; the owner stays root
  $ sudo chmod 640 /etc/analytics/analytics.conf
    => 6 = owner read+write, 4 = group read, 0 = others nothing
  $ sudo chmod 755 /etc/analytics
    => 7 = owner everything, 5 = read + enter for group and others
    => or 750 with group analytics (others can't even enter)
  $ sudo systemctl restart analytics
    => or just wait: Restart=on-failure retries every 3 s

## 4 VERIFY
SAY: "Running, staying running, as the right user, and the password is
      still not exposed."
  $ systemctl is-active analytics
    => active, and still active 10 s later
  $ ps aux | grep analytics
    => analyti+  273 ... /usr/bin/python3 -u /opt/analytics/analytics.py
    => the user column is cut to 8 characters: analyti+ = analytics,
       not root. Ignore the line ending "grep analytics" (that is you)
  $ ls -l /etc/analytics/analytics.conf
    => -rw-r----- 1 root analytics ...   (no sudo needed now)
  $ sudo -u nobody cat /etc/analytics/analytics.conf
    => Permission denied: an unrelated user still cannot read the camera
       login

TRAP
  - `chmod 777` / `chmod 644` "fixes" it by publishing the camera password
    to every local user (and 777 lets any of them rewrite the config).
  - Running the service as root also silences the error and hands root to
    the daemon.
  - Fixing only the file while the directory is still 0700 root: same
    error, no progress, `namei -l` is how you see it.
  - `chown analytics` + 600 is acceptable too (it works and has no world
    bits), root:analytics 640 is the tidier answer.

DO IT BETTER
  - Ask in order: who runs it, who owns the file, who can reach it. Read
    `ls -l` left to right.
  - Reproduce it as the service user (sudo -u analytics) before you
    change anything.
  - Check every directory on the path with `namei -l`, not just the file.
  - Least privilege: root keeps ownership, the group reads, nobody else.
