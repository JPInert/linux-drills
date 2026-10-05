# service-exec-fail: feed relay won't start after the vendor update

WEAK SPOT    reading systemd's exit codes instead of guessing, and knowing
             systemd caches unit files. 203/EXEC = it could not even RUN
             the ExecStart file (permissions or path). 200/CHDIR = bad
             WorkingDirectory. The app never started, so no app log will
             help: the answer is in the unit's own journal.
LOCAL-FIRST  nothing about this involves the network. Also: a unit edit
             means `daemon-reload`.

THE SHORT FORMS (this is all you type)
  systemctl status feedrelay             the exit code (status=203/EXEC)
  sudo journalctl -u feedrelay -n 20     the unit's own journal
  ls -l /opt/feedrelay/bin/run.sh        the file's permission bits
  sudo chmod 755 /opt/feedrelay/bin/run.sh
                                         give it the execute bit
  systemctl cat feedrelay                the unit systemd has now
  sudo nano /etc/systemd/system/feedrelay.service
                                         fix the unit by hand
  sudo systemctl daemon-reload           after ANY hand edit of a unit
  sudo systemctl restart feedrelay       try again
  curl -s localhost:8091                 does it answer?

## 1 OBSERVE
SAY: "It fails instantly, so it's systemd failing to launch it, not the
      app crashing. Status first, then the unit's journal."
  $ systemctl status feedrelay
    => Active: failed (Result: exit-code)
    => Process: ... ExecStart=/opt/feedrelay/bin/run.sh
       (code=exited, status=203/EXEC)
  $ sudo journalctl -u feedrelay -n 20
    => -u = only this unit's lines   -n 20 = only the last 20 lines
    => Failed to locate executable /opt/feedrelay/bin/run.sh:
       Permission denied
    => Failed at step EXEC spawning ...: Permission denied

## 2 NARROW
SAY: "Permission denied on the launcher. The file is there, so it's the
      mode bits, not a typo in the path."
  $ ls -l /opt/feedrelay/bin/run.sh
    => -l = long listing: permissions, owner, size, date
    => -rw-r--r-- 1 root root 98 ... run.sh
    => r = read, w = write, x = execute: there is no x anywhere
    => the 'redeployed from a zip' story
  $ ls -ld /opt/feedrelay /opt/feedrelay/bin
    => -d = show the folder itself, not what is inside it
    => drwxr-xr-x ... both folders have x, so they are fine
SAY: "Give it the execute bit, restart, and read the status AGAIN.
      Don't assume that was the only problem."
  $ sudo chmod 755 /opt/feedrelay/bin/run.sh
    => 755 = owner read+write+run, everyone else read+run
    => ls -l now shows -rwxr-xr-x
  $ sudo systemctl restart feedrelay
  $ systemctl status feedrelay
    => still failed, and the code CHANGED: status=200/CHDIR
  $ sudo journalctl -u feedrelay -n 5
    => Changing to the requested working directory failed: No such
       file or directory
    => Failed at step CHDIR ...
  $ systemctl cat feedrelay
    => cat = print the unit file systemd is using
    => WorkingDirectory=/opt/feedrelay/current
  $ ls /opt/feedrelay
    => bin  relay.py    <- no `current` folder: v3 dropped that layout

## 3 ACT
SAY: "The unit is stale. I'll fix its WorkingDirectory, and I have to
      tell systemd I edited it, or it keeps the old copy."
  $ sudo nano /etc/systemd/system/feedrelay.service
    => change the line to:  WorkingDirectory=/opt/feedrelay
    => save with Ctrl+O, Enter, then exit with Ctrl+X
  $ sudo systemctl daemon-reload
    => re-read unit files from disk. Skip it and systemctl warns:
       "The unit file ... changed on disk. Run 'systemctl
       daemon-reload'" and restart runs the OLD copy (fails again)
  $ sudo systemctl restart feedrelay
  (or `sudo systemctl edit --full feedrelay`: it opens the unit in an
  editor and reloads by itself when you save)

## 4 VERIFY
SAY: "Running, still enabled, and answering. And the process is the
      unit's, not one I started."
  $ systemctl status feedrelay
    => Active: active (running)
    => Main PID: 215 (python3)
  $ systemctl is-enabled feedrelay
    => enabled
  $ curl -s localhost:8091
    => -s = silent, no progress bar
    => feedrelay ok: 4 streams relayed
  $ sudo ss -tlnp | grep 8091
    => -t TCP  -l listening  -n numbers  -p which program (needs sudo)
    => 0.0.0.0:8091 ... users:(("python3",pid=215,fd=3))
    => pid = the Main PID above

TRAP
  - `chmod 777` "works" but leaves a world-writable launcher: 755 is
    right (the check accepts 777, and says so).
  - Editing the unit and restarting WITHOUT `daemon-reload` reruns the
    old definition and fails identically.
  - `bash /opt/feedrelay/bin/run.sh &` brings the port up outside
    systemd; the unit stays failed and dies at reboot.
  - Making a fake /opt/feedrelay/current symlink also works, but papers
    over a stale unit file.

DO IT BETTER
  - Read the exit code, don't guess: 203/EXEC = can't RUN the file,
    200/CHDIR = bad WorkingDirectory.
  - After each fix, read the status AGAIN: the code can change.
  - A hand edit of a unit means `daemon-reload`.
  - Verify the process is the unit's (Main PID), not one you started.
