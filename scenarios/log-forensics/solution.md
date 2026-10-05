# log-forensics: three facts out of two logs (grep / sort | uniq -c)

WEAK SPOT    filtering. Count the RIGHT lines (filter first), the RIGHT
             field, the RIGHT window. Build a pipeline one `|` at a time
             and look at the output after every step.
LOCAL-FIRST  it is all on this box; no network tool is ever the answer to
             "what is in this file".

THE SHORT FORMS (this is all you type)
  cd /var/log/nvr                    work next to the logs
  head -3 auth.log                   raw shape first, before any pattern
  grep 'AUTH FAIL' auth.log          filter FIRST: failed logins only
  grep -o 'ip=[0-9.]*'               keep just the ip=... part
  sort | uniq -c | sort -rn | head -3
                                     count per value, biggest first
  grep '^2026-09-23 02:' access.log  the window: date + hour at line START
  awk '{print $6}'                   keep only word 6 (the status)
  awk '{print $6, $5}'               keep word 6 (status) + 5 (path)
  grep '^404 '                       lines that START with 404
  wc -l                              count the lines

## 1 OBSERVE
SAY: "Before I write a pattern I'll look at the raw shape of both logs."
  $ cd /var/log/nvr
    => every number below is from ONE run: the logs are new each start
  $ wc -l auth.log access.log
    => wc -l = count lines
    => 1246 auth.log   38421 access.log: far too many to read by eye
  $ head -3 auth.log
    => head -3 = only the first 3 lines
    => 2026-09-22 00:01:04 AUTH FAIL user=admin ip=10.50.9.73
       reason=bad_password
    => 2026-09-22 00:01:56 AUTH OK   user=operator ip=10.50.2.24
    => FAIL and OK lines are mixed, and both have an ip=
  $ head -3 access.log
    => 2026-09-22 00:00:04 10.50.2.14 GET /static/app.js 200 11891 ...
    => words: 1 date  2 time  3 ip  4 method  5 path  6 STATUS  7 bytes
    => status is word 6. Word 7 (bytes) is a number too: the trap

## 2 NARROW
SAY: "1) Filter to FAILED logins, pull out the ip, then count per
      value. One step at a time."
  $ grep 'AUTH FAIL' auth.log | head -3
    => | = feed the output into the next command
    => only FAIL lines now: ... AUTH FAIL user=admin ip=10.50.9.73 ...
  $ grep 'AUTH FAIL' auth.log | grep -o 'ip=[0-9.]*' | head -3
    => -o = print only the part that matched, not the whole line
    => [0-9.]* = any run of digits and dots
    => ip=10.50.9.73
    => ip=10.50.9.73
    => ip=10.50.9.43
  $ grep 'AUTH FAIL' auth.log | grep -o 'ip=[0-9.]*' | sort | \
      uniq -c | head -3
    => sort puts equal lines next to each other; uniq -c then counts
       each run (uniq only merges NEIGHBOURS, so always sort first)
    => 3 ip=10.50.2.10 / 2 ip=10.50.2.12 / 5 ip=10.50.2.13
  $ grep 'AUTH FAIL' auth.log | grep -o 'ip=[0-9.]*' | sort | \
      uniq -c | sort -rn | head -3
    => sort -rn = sort by number (-n), biggest first (-r = reverse)
    => 191 ip=10.50.9.73    <- answer 1: ip=10.50.9.73 fails=191
    => 108 ip=10.50.9.45
    =>  59 ip=10.50.9.43

SAY: "2) The window is a date and an hour at the START of the line, and
      the status is word 6, not any number on the line."
  $ grep '^2026-09-23 02:' access.log | head -3
    => ^ = the line must START here, so 02: is the hour, not a minute
    => 2026-09-23 02:00:10 10.50.2.15 GET /static/app.js 200 4851 ...
  $ grep '^2026-09-23 02:' access.log | awk '{print $6}' | head -3
    => awk '{print $6}' = print only the 6th word of each line
    => 200 / 200 / 200
  $ grep '^2026-09-23 02:' access.log | awk '{print $6}' | \
      grep '^5' | head -3
    => grep '^5' = keep values that START with 5 (500-599)
    => 502 / 503 / 503
  $ grep '^2026-09-23 02:' access.log | awk '{print $6}' | \
      grep '^5' | wc -l
    => 90    <- answer 2: 5xx=90

SAY: "3) Only the 404s, then the camera number out of the path."
  $ awk '{print $6, $5}' access.log | head -3
    => print word 6 (status), a space, then word 5 (path)
    => 200 /static/app.js
    => 200 /api/cam/2/snapshot
  $ awk '{print $6, $5}' access.log | grep '^404 ' | head -3
    => now status is first on the line, so ^404 can only hit status
    => 404 /api/cam/4/snapshot
  $ awk '{print $6, $5}' access.log | grep '^404 ' | \
      grep -o 'cam/[0-9]*' | head -3
    => cam/4 / cam/7 / cam/4
  $ awk '{print $6, $5}' access.log | grep '^404 ' | \
      grep -o 'cam/[0-9]*' | sort | uniq -c | sort -rn | head -3
    => 95 cam/7    <- answer 3: cam=7
    => 46 cam/1
    => 42 cam/5

## 3 ACT
SAY: "I have all three facts. This is a diagnose-only ticket, so I
      report them."
  $ answer "ip=10.50.9.73 fails=191 5xx=90 cam=7"
    => use YOUR numbers: the logs are new every time the drill starts

## 4 VERIFY
SAY: "Sanity-check the biggest number a second way before I say it."
  $ grep 'ip=10.50.9.73 ' auth.log | grep -c FAIL
    => -c = print how many lines matched, instead of the lines
    => 191, same as the pipeline
  $ grep -o 'ip=[0-9.]*' auth.log | sort | uniq -c | sort -rn | head -3
    => 531 ip=10.50.9.45   <- the SAME count without the FAIL filter:
       a busy IP with lots of OK logins wins. That is the trap.
  $ check

TRAP
  - `grep ip=X auth.log | wc -l` counts OK logins too (one busy
    legit-looking IP outnumbers the attacker: 531 vs 191).
  - `grep ' 5[0-9][0-9] '` also matches the BYTES column: 100, not 90.
  - `grep ' 404 '` has the same bug, just smaller (356 lines, not 355).
  - A bare `grep 02:` matches any 02: in the line, and the whole day is
    not the 02:00 hour.
  - `uniq -c` without `sort` first splits one IP into many small counts.

DO IT BETTER
  - Read a few raw lines first, then write the pattern.
  - Filter to the RIGHT lines (AUTH FAIL) before you count.
  - Match the RIGHT field (word 6), not any number in the line.
  - Add one `|` at a time, with `| head -3` on the end to look.
  - Sanity-check the biggest number a second way before you say it.
