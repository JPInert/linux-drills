# disk-full-deleted: deleted the big log, disk still 100%

WEAK SPOT    df vs du. df asks the FILESYSTEM how many blocks are used; du
             adds up the FILES it can see. A file that was `rm`'d while a
             process still has it open is invisible to du but keeps every
             block until that process closes it. `lsof` (never "ldisk") is
             the tool for it, and it needs sudo to see other users'
             processes.
LOCAL-FIRST  Local-first: no network tool.

THE SHORT FORMS (this is all you type)
  df -h /var/log               what the FILESYSTEM says is used
  sudo du -sh /var/log         what the visible FILES add up to
  sudo lsof +L1                open files that were deleted (still held)
  systemctl status cam-poller  is it up, and its Main PID
  sudo ls -l /proc/PID/fd      same answer without lsof
  cat /etc/cam-poller.conf     why it wrote so much
  sudo nano /etc/cam-poller.conf         set TRACE=off
  sudo systemctl restart cam-poller      closes the file, frees the space

## 1 OBSERVE
SAY: "Alert says /var/log is full, and someone already deleted the big
      log. Which view is right? I'll compare df and du."
  $ df -h /var/log
    => df = disk free. -h = human sizes (M, G)
    => tmpfs   48M   48M     0 100% /var/log
  $ sudo du -sh /var/log
    => du = disk usage. -s = one total. -h = human sizes
    => 2.4M   <- df and du disagree by ~45 MB: space is held by
       something du cannot see
  $ ls -la /var/log/cam-poller/
    => -l = long list, -a = show hidden files too
    => only . and .. : the log folder is empty
  $ sudo journalctl -u cam-poller -n 5
    => -u = only this unit (service). -n 5 = the last 5 lines
    => ERROR poll: cannot write /var/log/cam-poller/poll.log:
       [Errno 28] No space left on device

## 2 NARROW
SAY: "Missing space with a deleted file means something still has it
      open. I'll list open files that no longer have a name."
  $ sudo lsof +L1
    => lsof = list open files. +L1 = only files with less than 1 name
       (link) left, i.e. deleted but still open
    => cam-polle 113 camd 3w REG ... 47820800 0 ... poll.log (deleted)
    => PID 113 (yours will differ) holds it as file descriptor 3:
       47 MB, 0 names left
  $ systemctl status cam-poller
    => Main PID: 113 (cam-poller): the service owns that PID
  $ sudo ls -l /proc/113/fd
    => the same thing without lsof: every file PID 113 has open
    => 3 -> /var/log/cam-poller/poll.log (deleted)
  $ cat /etc/cam-poller.conf
    => TRACE=on: "Turned on last week for a camera bug, never turned
       off." That is why it wrote 45 MB
SAY: "Two problems: the space is pinned by the open file, and the cause
      is still running. Fixing only one comes back."

## 3 ACT
SAY: "Fix the cause, then make the holder let go. Restarting the service
      closes the file and the kernel frees its space."
  $ sudo nano /etc/cam-poller.conf
    => change TRACE=on to TRACE=off. Ctrl-O Enter saves, Ctrl-X quits
    => or in one line, no editor:
  $ sudo sed -i 's/^TRACE=.*/TRACE=off/' /etc/cam-poller.conf
    => -i = edit the file in place. s/OLD/NEW/ = replace OLD with NEW
    => ^TRACE=.* = the whole line that starts with TRACE=
  $ sudo systemctl restart cam-poller
    => a service that must stay up: restart, do not stop

  alternative if it cannot be restarted right now:
  $ sudo truncate -s 0 /proc/113/fd/3
    => -s 0 = set the size to 0: empties the deleted file through the
       program's own open handle (fd 3 from lsof)
    => but the config still has to change and the daemon restarted, or
       it refills at ~600 KB/s

  optional, stops it recurring: /etc/logrotate.d/cam-poller with
  copytruncate and maxsize

## 4 VERIFY
SAY: "Space is back, nothing deleted is still held, the poller is running
      and the log is quiet."
  $ df -h /var/log
    => tmpfs   48M  2.4M   46M   5% /var/log
  $ sudo lsof +L1
    => no output: nothing deleted is held any more
  $ systemctl is-active cam-poller
    => active
  $ tail -3 /var/log/cam-poller/poll.log
    => tail -3 = the last 3 lines
    => INFO  poll: cams=4 online=4 rtt_ms=16, one line every 5 s
  $ check

TRAP
  - Deleting MORE files frees megabytes of the 48 that are pinned: the
    visible logs were never the problem.
  - `du` hunting only ever finds what is visible.
  - Truncating through /proc/PID/fd or restarting without setting
    TRACE=off frees the space for about a minute.
  - Editing the config without restarting changes nothing: the daemon
    only reads it at start and still holds the deleted file.
  - Stopping the poller "works" and takes camera status down.
  - `lsof +L1` without sudo cannot see camd's files, and on this box it
    just sits there (Ctrl-C). lsof wants sudo.

DO IT BETTER
  - df and du disagree? Something still holds a deleted file:
    sudo lsof +L1
  - Two problems, fix both: the cause (TRACE=off) and the holder
    (restart).
  - Restart, do not stop: camera status must stay up.
