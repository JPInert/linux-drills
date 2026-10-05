# unit-masked: the camera list is stale, the sync job never runs

WEAK SPOT    enabled / disabled / masked are three different things.
             `disable` only removes the boot-time link. `mask` links the
             unit to /dev/null so NOTHING can start it (not you, not a
             timer, not a dependency), and only `unmask` takes that off.
             Also: a timer and the service it triggers are two units with
             two states.
LOCAL-FIRST  "cameras offline" here is stale DATA on the NVR, not a dead
             network.

THE SHORT FORMS (this is all you type)
  systemctl status feedrelay-sync              Loaded: masked?
  systemctl list-unit-files | grep feedrelay   service AND timer states
  systemctl cat feedrelay-sync.timer           the schedule (OnCalendar)
  sudo systemctl unmask feedrelay-sync.service       take the mask off
  sudo systemctl start feedrelay-sync.service        run it once now
  sudo systemctl enable --now feedrelay-sync.timer   schedule back on
  systemctl list-timers | grep feedrelay       when is the NEXT run?

## 1 OBSERVE
SAY: "The list hasn't refreshed in a week. Is the sync job running? Try
      it and read exactly what systemctl says."
  $ sudo systemctl start feedrelay-sync
    => Failed to start feedrelay-sync.service: Unit feedrelay-sync.service
       is masked.
  $ systemctl status feedrelay-sync
    => Loaded: masked (Reason: Unit feedrelay-sync.service is masked.)
    => Active: inactive (dead)
  $ cat /var/lib/feedrelay/last-sync
    => 2026-09-19T03:15:02Z
    => last week: the job writes the time here each time it runs

## 2 NARROW
SAY: "Masked is not a crash. Someone did this on purpose. What is it,
      what else is off, and is the real unit still there?"
  $ ls -l /etc/systemd/system/feedrelay-sync.service
    => -l = long listing: shows where a link points
    => feedrelay-sync.service -> /dev/null
    => the mask: a link to "nothing" that hides the real unit
  $ ls -l /usr/lib/systemd/system/feedrelay-sync.*
    => feedrelay-sync.service  and  feedrelay-sync.timer
    => the real service and timer are intact underneath
  $ systemctl list-unit-files | grep feedrelay
    => lists every unit and its state; grep keeps our two
    => feedrelay-sync.service    masked    enabled
    => feedrelay-sync.timer      disabled  enabled
    => first word = its state now; ignore the second (the vendor default)
  $ systemctl status feedrelay-sync.timer
    => Loaded: loaded (...; disabled; ...)   Active: inactive (dead)
  $ systemctl cat feedrelay-sync.timer
    => cat = print the unit file systemd is using
    => OnCalendar=*:0/15
    => every 15 minutes
SAY: "Monday's troubleshooter masked the service and turned the schedule
      off. Two things to undo, and I'll run it now to catch up."

## 3 ACT
SAY: "Unmask the service, run it once now (it is a oneshot: it runs and
      exits), then switch the schedule back on and enabled."
  $ sudo systemctl unmask feedrelay-sync.service
    => Removed "/etc/systemd/system/feedrelay-sync.service".
    => (only the /dev/null link is removed, not the real unit)
  $ sudo systemctl start feedrelay-sync.service
    => no output = it ran and finished
  $ sudo systemctl enable --now feedrelay-sync.timer
    => enable = start it at every boot   --now = and start it right now
    => Created symlink .../timers.target.wants/feedrelay-sync.timer

## 4 VERIFY
SAY: "It ran, and it will run again by itself: both the effect and the
      schedule."
  $ cat /var/lib/feedrelay/last-sync
    => today's date and time, e.g. 2026-09-25T14:20:59Z
  $ sudo journalctl -u feedrelay-sync | tail -5
    => -u = only this unit's log lines   tail -5 = only the last 5
    => feedrelay-sync: 4 camera definitions synced
    => Finished feedrelay-sync.service
  $ systemctl list-timers | grep feedrelay
    => Fri 2026-09-25 14:30:00 UTC 8min left ... feedrelay-sync.timer
    => NEXT run inside the coming 15 minutes
  $ systemctl list-unit-files | grep feedrelay
    => feedrelay-sync.service    static
    => feedrelay-sync.timer      enabled
    => static = no boot setting of its own: the timer starts it
  $ check

TRAP
  - `enable` and `start` do not override a mask. `disable` is not
    `unmask`.
  - Enabling only the timer changes nothing: every tick still hits the
    masked service (the timer will not even stay active).
  - `cp` a fresh unit file over the mask: cp follows the link and
    writes into /dev/null. The link stays.
  - Running /usr/local/sbin/feedrelay-sync by hand refreshes the list
    once and leaves the schedule broken.
  - (`rm` of the /dev/null link also unmasks; `systemctl unmask` is
    the clean, intended way.)

DO IT BETTER
  - Read exactly what systemctl says: masked is not a crash.
  - Two units, two states: undo the service mask AND re-enable the timer.
  - Verify the effect AND the schedule: last-sync, then list-timers.
