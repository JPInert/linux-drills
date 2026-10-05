# cpu-peg: everything is slow, something is eating the CPU

WEAK SPOT    going straight to `kill PID` and never asking "who started
             this, and why does it come back?" And knowing where your
             job ends: stop it to restore service, then TELL the owner.
             Switching a feature off for good is their call.
LOCAL-FIRST  Local-first: a laggy dashboard and a laggy SSH session on a
             box that answers ping is a CPU/memory/disk question, not a
             network one.

THE SHORT FORMS (this is all you type)
  top                                   busiest program first (q = quit)
  ps aux | grep frame-indexer           its PID and user, in one line
  systemctl status frame-indexer        is it a service? is it enabled?
  systemctl cat frame-indexer           Restart=always? kill won't stick
  sudo journalctl -u frame-indexer -n 10
                                        what it is doing: the EVIDENCE
  sudo systemctl stop frame-indexer     stop the unit, not the PID
  sudo systemctl set-property frame-indexer CPUQuota=20%
                                        or: keep it running, capped
  systemctl is-enabled frame-indexer    still enabled: back at reboot
  systemctl is-active videoproc nvr-web analytics
                                        nothing else went down

## 1 OBSERVE
SAY: "Slow box, network is fine. First: is it CPU, memory, disk or
      network? I'll look at CPU per program."
  $ top
    => a live list, busiest first. It sorts by %CPU already (press P to
       be sure, M to sort by memory, q to quit)
    => 143 root ... R  86.7  ... frame-i+   <- one program near 100%
    => the name is cut off with "+": the next command shows it in full
  $ ps aux | grep frame-indexer
    => a = every user's programs, u = show the user and %CPU,
       x = include ones with no terminal (services)
    => root  143 94.8 ... /usr/bin/python3 /opt/frame-indexer/frame-indexer
    => the line ending "grep frame-indexer" is your own search: ignore it
  the small stuff (videoproc a few %, nvr-web, analytics) is normal:
  leave it alone

## 2 NARROW
SAY: "frame-indexer is pegging a core. Is it a service? Who owns it, and
      what does systemd do when it dies?"
  $ systemctl status frame-indexer
    => Loaded: ... enabled      <- starts at every boot
    => Active: active (running), Main PID: 143, CPU: keeps climbing
  $ systemctl cat frame-indexer
    => cat = print the unit file systemd is really using
    => Restart=always, RestartSec=1  <- why a kill won't stick
  $ sudo journalctl -u frame-indexer -n 10
    => -u = only this unit's log, -n 10 = the last 10 lines
    => (without sudo you see "insufficient permissions": that is normal)
    => "0 frames indexed, queue still 0, starting over": a stuck loop,
       not real work

## 3 ACT
SAY: "I could kill the PID, but systemd will just start it again. I'll
      stop the unit. That gets the box back now. Whether thumbnail
      search stays off for good is the owner's call, not mine."
  $ sudo kill -9 143
    => use the PID from top. This is the trap: try it once
    => -9 = force kill, no chance to clean up
  $ ps aux | grep frame-indexer
    => a NEW PID (230), same ~93%: systemd restarted it within 1 s
  $ sudo systemctl stop frame-indexer
    => stop = end it now, and systemd will not restart it
    => it stays ENABLED: it starts again at the next boot. That is on
       purpose: turning a feature off for good is not a triage step
  or, if they need thumbnail search running today, cap it instead:
  $ sudo systemctl set-property frame-indexer CPUQuota=20%
    => CPUQuota=20% = at most 20% of one CPU; the rest is free again
    => set-property applies it now AND keeps it after a reboot
       (systemd writes the setting to a small file under /etc)
    => the loop is still broken, but the box is usable and the
       feature is still on
  only if the owner says "keep it off":
      sudo systemctl disable frame-indexer
      (disable = don't start it at boot; that switches thumbnail
       search off silently until someone turns it back on)

## 4 VERIFY
SAY: "Confirm the CPU is back, I did not take anything else down, and
      note what happens at the next reboot."
  $ top
    => nothing above a few percent (or frame-indexer at ~20% if capped)
  $ systemctl is-active videoproc nvr-web analytics
    => active  active  active  (one line per unit you named)
  $ systemctl is-enabled frame-indexer
    => enabled   <- it comes back at reboot: say so in the ticket
  $ check
SAY: "Ticket note: stopped frame-indexer, it was looping with '0 frames
      indexed, queue still 0, starting over' and pegging the CPU. Still
      enabled, so it returns at reboot until the owner fixes it."

TRAP
  - `sudo kill -9 PID` / `sudo killall frame-indexer` on a unit with
    Restart=always: gone for one second, back under a new PID.
  - `renice` does nothing when no one else wants the CPU.
  - `kill -STOP` freezes it, it is still there.
  - Stopping every busy-looking service takes the dashboard and analytics
    down with the culprit.
  - `disable` on your own: the box is fine, and thumbnail search is
    silently gone until someone notices. That is the owner's decision.

DO IT BETTER
  - Per-process view first (top), not the load average.
  - Before any kill, ask "who started this, and why does it come back?":
    systemctl cat shows Restart=always.
  - Stop the unit (the ACT), or cap it with CPUQuota to keep the
    feature. Disable only if the owner says so.
  - ESCALATE / TELL THE OWNER: what you stopped, the evidence (the log
    line), and that it is still enabled so it returns at reboot.
  - Verify everything else is still active.
