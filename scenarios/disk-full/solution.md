# disk-full: log partition at 100%

WEAK SPOT    df / du / fdisk.  df = which FILESYSTEM is full.
             du = WHAT is filling it.  fdisk = partition tables: it is
             never the answer to "disk full".
LOCAL-FIRST  Yes, it is local. No network tool needed.

THE SHORT FORMS (this is all you type)
  df -h                        which FILESYSTEM is full (look for 100%)
  df -i /var/log               out of inodes? (rule that out)
  sudo du -sh /var/log/*       size of each thing in /var/log
  ls -lh /var/log/analytics/   the files, with human sizes
  sudo grep LOG_LEVEL /etc/analytics/analytics.conf     why it grew
  sudo truncate -s 0 FILE      empty a log IN PLACE (rm would free nothing)
  sudo nano /etc/analytics/analytics.conf     set LOG_LEVEL=INFO
  sudo systemctl restart analytics            so it reads the new level
  sudo lsof +L1                deleted-but-still-open files (the rm trap)

## 1 OBSERVE
SAY: "Alert says disk. Before anything else I'll check which filesystem
      is full."
  $ df -h
    => df = disk free. -h = human sizes (M, G) instead of block counts
    => tmpfs   48M   48M   0   100%  /var/log       <- this one, not /
  $ df -i /var/log
    => -i = count inodes (file slots) instead of bytes
    => IUse% 1%: plenty of file slots, so it really is bytes
  $ systemctl status analytics
    => active (running): up, but...
  $ sudo journalctl -u analytics -n 20
    => -u = only this unit (service). -n 20 = the last 20 lines
    => ERROR detect: cannot write /var/log/analytics/detect.log:
       [Errno 28] No space left on device

## 2 NARROW
SAY: "/var/log is full. Now what is in it? du adds up sizes on disk."
  $ sudo du -sh /var/log/*
    => du = disk usage. -s = one total per item (not every subfolder)
    => -h = human sizes. /var/log/* = each thing inside /var/log
    => 48M  /var/log/analytics      everything else is ~0
  $ ls -lh /var/log/analytics/
    => -l = long list (size, owner, date). -h = human sizes
    => detect.log 46M, the two .gz files 1.5M and 880K
  $ tail -3 /var/log/analytics/detect.log
    => tail -3 = the last 3 lines
    => DEBUG detect: frame=88123 cam=cam-02 ... over and over
  $ sudo grep LOG_LEVEL /etc/analytics/analytics.conf
    => the file is readable by root only, hence sudo
    => LOG_LEVEL=DEBUG                              <- the cause

## 3 ACT
SAY: "The daemon holds this file open, so rm would free nothing. I'll
      truncate it in place, then fix the cause and restart so it
      can't refill."
  $ sudo truncate -s 0 /var/log/analytics/detect.log
    => -s 0 = set the file's size to 0. Same file, now empty
  $ sudo nano /etc/analytics/analytics.conf
    => change LOG_LEVEL=DEBUG to LOG_LEVEL=INFO
    => Ctrl-O then Enter saves, Ctrl-X quits
    => or in one line, no editor:
  $ sudo sed -i 's/^LOG_LEVEL=.*/LOG_LEVEL=INFO/' \
      /etc/analytics/analytics.conf
    => -i = edit the file in place. s/OLD/NEW/ = replace OLD with NEW
    => ^LOG_LEVEL=.* = the whole line that starts with LOG_LEVEL=
  $ sudo systemctl restart analytics
    => it only reads its config when it starts

  Optional, stops it recurring. Put this in /etc/logrotate.d/analytics
  (sudo nano /etc/logrotate.d/analytics):
      /var/log/analytics/detect.log {
          daily
          maxsize 20M
          rotate 4
          compress
          copytruncate
          missingok
      }
  $ sudo logrotate -d /etc/logrotate.d/analytics
    => -d = dry run: shows what it WOULD do, changes nothing
    => "log does not need rotating": the rule reads fine

## 4 VERIFY
SAY: "Confirming space is back, the service is up, and the log is quiet."
  $ df -h /var/log
    => naming a folder shows only its filesystem
    => tmpfs   48M  2.4M   46M   5% /var/log
  $ systemctl is-active analytics
    => active
  $ tail -f /var/log/analytics/detect.log
    => -f = follow: keep printing new lines as they arrive
    => INFO detect: cams=4 fps=24.0 device=cuda:0 every ~5 s
    => Ctrl-C to stop watching
  $ check

TRAP
  - `rm detect.log` on a file a daemon has open frees NOTHING: df stays
    at 100%. Find such files with:  sudo lsof +L1
    (lsof = list open files. +L1 = only files with less than 1 name
    left, i.e. deleted but still held open)
  - Truncating without changing LOG_LEVEL fixes the symptom for
    3 minutes.
  - `grep` on the config without sudo says "Permission denied": that is
    the file's mode, not the fault.

DO IT BETTER
  - Two questions, two tools: df -h (WHICH filesystem), then du (WHAT).
  - Fix the cause (LOG_LEVEL), not only the symptom (the big file).
  - Verify by watching it: df -h, then tail -f for a few seconds.
