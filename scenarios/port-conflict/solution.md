# port-conflict: dashboard won't start, something else has :8080

WEAK SPOT    lsof (not "ldisk"), kill (not rfkill), and sudo. Also: plain
             `ss -tlnp` as a normal user hides other users' process
             names. Use sudo.
LOCAL-FIRST  nothing here needs ping.

THE SHORT FORMS (this is all you type)
  systemctl status dashboard             is it running? (failed)
  sudo journalctl -u dashboard -n 20     why it failed (Errno 98?)
  sudo ss -tlnp | grep 8080              who owns the port (sudo = names)
  sudo lsof -i :8080                     same answer, different tool
  ps aux | grep PID                      who, what, started when
  sudo kill PID                          SIGTERM: politely first
  sudo kill -9 PID                       SIGKILL: last resort
  sudo systemctl start dashboard         start the real one
  curl -s localhost:8080 | grep title    is it the dashboard page?

## 1 OBSERVE
SAY: "Service down. First: what does systemd say, and why did it fail?"
  $ systemctl status dashboard
    => Active: failed (Result: exit-code)
    => enabled: it DID try to start at boot, and it failed
  $ sudo journalctl -u dashboard -n 20
    => -u = only this unit's lines   -n 20 = only the last 20 lines
    => OSError: [Errno 98] Address already in use

## 2 NARROW
SAY: "Address already in use means another process owns 8080. Who?"
  $ sudo ss -tlnp | grep 8080
    => -t TCP  -l listening  -n numbers  -p which program (needs sudo)
    => 0.0.0.0:8080 ... users:(("python3",pid=114,fd=3))
    => your PID will differ: use the number after pid=
    => without sudo the users:(...) part is simply missing
  $ sudo lsof -i :8080
    => -i :8080 = whatever has network port 8080 open
    => python3 114 deploy ... TCP *:http-alt (LISTEN)
    => http-alt is just the name /etc/services gives port 8080
  $ ps aux | grep 114
    => a = all users  u = show the user  x = no terminal too
    => deploy  114 ... 14:19 ... python3 /home/deploy/preview.py
    => columns: USER, PID, ..., START (when), COMMAND (what)
    => ignore the `grep 114` line: that is your own search
SAY: "It's a stale preview server run by deploy, not part of the
      service. Safe to stop."

## 3 ACT
SAY: "Terminate it politely first, then check it's gone before
      escalating."
  $ sudo kill 114
    => plain kill sends SIGTERM: "please exit"
  $ sudo ss -tlnp | grep 8080
    => still there: this one ignores SIGTERM
  $ sudo kill -9 114
    => -9 = SIGKILL: it can't be caught or ignored. Last resort.
  $ sudo ss -tlnp | grep 8080
    => prints nothing: the port is free
  $ sudo systemctl start dashboard

## 4 VERIFY
SAY: "Confirm the port is now the dashboard, and that it survives a
      reboot."
  $ systemctl is-active dashboard
    => active
  $ systemctl is-enabled dashboard
    => enabled (it will start at the next boot)
  $ curl -s localhost:8080 | grep title
    => -s = silent, no progress bar
    => <title>Facility Dashboard</title>
    => nothing? wait a second and try again: it is still starting
  $ sudo ss -tlnp | grep 8080
    => python3 with a NEW pid: the Main PID in `systemctl status`

TRAP
  - `systemctl restart dashboard` in a loop never works while the
    squatter lives.
  - Changing the dashboard's port "fixes" it and breaks every wall
    display.
  - fuser also works:  `sudo fuser -n tcp 8080` shows the PID
    (-n tcp = look at TCP ports), and `sudo fuser -k -n tcp 8080`
    kills it (-k = kill).

DO IT BETTER
  - Errno 98 = Address already in use: find who owns 8080, don't
    restart in a loop.
  - Use sudo with ss/lsof, or other users' process names stay hidden.
  - SIGTERM first, check it's gone, then kill -9 as a last resort.
  - Verify it survives a reboot: is-active AND is-enabled.
