# service-not-enabled: camera feeds "unreachable" since the reboot

WEAK SPOT    assuming "connection refused from the guard station" means
             the NETWORK. Refused means the box answered with a reset: a
             packet got there and NOTHING was listening. Also: running
             now and starting at boot are two separate systemd states
             (active vs enabled).
LOCAL-FIRST  ping working + refused = look at the box.

THE SHORT FORMS (this is all you type)
  sudo ss -tlnp                          what is listening (8090?)
  curl localhost:8090                    ask the port from the box itself
  systemctl status camwatch              Loaded: disabled? Active: dead?
  sudo journalctl -u camwatch -n 20      did it ever try and fail?
  systemctl is-enabled camwatch          enabled or disabled at boot
  systemctl cat camwatch                 the unit file itself
  sudo systemctl enable --now camwatch   start now AND enable for boot
  systemctl is-active camwatch           running now?

## 1 OBSERVE
SAY: "Ping works and the port is refused, so the network path is fine.
      Something on the box isn't listening. Checking locally."
  $ sudo ss -tlnp
    => -t TCP  -l listening  -n numbers  -p which program (needs sudo)
    => only 0.0.0.0:22 (sshd). Nothing on 8090
  $ curl localhost:8090
    => curl: (7) Failed to connect to localhost port 8090 ...
       Couldn't connect to server
    => same answer from the box itself, so it is not the network
  $ systemctl status camwatch
    => Loaded: ... disabled; preset: enabled
    => Active: inactive (dead)

## 2 NARROW
SAY: "Not running, and 'disabled' means it was never set to start at
      boot. Did it ever try and fail?"
  $ sudo journalctl -u camwatch -n 20
    => -u = only this unit's lines   -n 20 = only the last 20 lines
    => -- No entries --
    => it never started this boot: not a crash, nobody started it
  $ systemctl is-enabled camwatch
    => disabled
  $ systemctl list-unit-files camwatch.service
    => UNIT FILE        STATE    PRESET
    => camwatch.service disabled enabled
    => STATE is THIS box. PRESET is only the distro default.
  $ systemctl cat camwatch
    => cat = print the unit file systemd is using
    => ExecStart=/usr/bin/python3 /opt/camwatch/camwatch.py
    => [Install] WantedBy=multi-user.target
SAY: "Unit is fine, the package installed it but nothing enabled it.
      Start it now AND enable it for boot."

## 3 ACT
SAY: "enable --now does both in one go."
  $ sudo systemctl enable --now camwatch
    => enable = start at every boot   --now = and start it right now
    => Created symlink .../multi-user.target.wants/camwatch.service

## 4 VERIFY
SAY: "Both states, then the actual port."
  $ systemctl is-active camwatch
    => active
  $ systemctl is-enabled camwatch
    => enabled
  $ curl -s localhost:8090
    => -s = silent, no progress bar
    => <html><head><title>camwatch relay</title> ... feeds: cam-01
       cam-02 cam-03 cam-04 up
  $ sudo ss -tlnp | grep 8090
    => 0.0.0.0:8090 ... users:(("python3",pid=177,fd=3))
    => pid = the Main PID in `systemctl status camwatch`
    => not a stray shell

TRAP
  - `systemctl start camwatch` alone brings the feeds back until the
    NEXT patch reboot (not enabled).
  - `systemctl enable camwatch` alone changes nothing right now (not
    started).
  - Running the python file by hand works from a shell, outside
    systemd, and dies with the session.
  - Flushing iptables / flapping links: the firewall was never the
    problem, and it leaves a hole behind.

DO IT BETTER
  - Refused = the box answered: look at the box, not the network.
  - Running now (active) and starting at boot (enabled) are two
    separate states: check both.
  - enable --now does both in one go.
  - Verify the listener is the unit's Main PID, not a stray shell.
