# config-hunt: which line really sets WATCHDOG_INTERVAL? (grep -r)

WEAK SPOT    grep hits are candidates, not answers. Apply the RULES of the
             program that reads the files.
LOCAL-FIRST  Local-first: read the README before you search.

THE SHORT FORMS (this is all you type)
  cat /etc/nvr/README          how the NVR loads config (the RULES)
  ls -l /etc/nvr/conf.d        what files exist
  grep -rn WATCHDOG_INTERVAL /etc/nvr /etc/default
                               every hit, with file and line (noisy)
  grep -n '^WATCHDOG_INTERVAL=' /etc/nvr/nvr.conf /etc/nvr/conf.d/*.conf
                               only real assignments, only loaded files,
                               in load order: the LAST line wins
  cat -n FILE                  show a file with line numbers, to confirm

## 1 OBSERVE
SAY: "First how the NVR loads config, then where the key appears."
  $ cat /etc/nvr/README
    => nvr.conf first, then conf.d/*.conf in name order
    => the LAST assignment wins; # lines are comments
    => files not ending in .conf (.dpkg-old, .disabled) are ignored
  $ ls -l /etc/nvr/conf.d
    => -l = long listing, one file per line
    => 10-cameras.conf  20-analytics.conf  50-site.conf  60-tuning.conf
    => 50-site.conf.dpkg-old  90-legacy.conf.disabled  <- never loaded

## 2 NARROW
SAY: "List every hit with file and line, then throw out what the loader
      ignores."
  $ grep -rn WATCHDOG_INTERVAL /etc/nvr /etc/default
    => -r = look inside every file under those folders
    => -n = print the line number after the file name
    => file:LINE:text, e.g. /etc/nvr/conf.d/50-site.conf:5:...=300
    => noisy: 8 hits. Cross out:
       nvr.conf:5:# WATCHDOG_INTERVAL=30          a comment
       10-cameras.conf:...WATCHDOG_INTERVAL_MAX   a different key
       /etc/default/nvr:...INTERVAL_OVERRIDE      different key + file
       .dpkg-old and .disabled                    not *.conf
    => the hits come out in disk order, NOT load order: don't pick
       the first or last one here
SAY: "Now I search only the files the loader reads, in its order."
  $ grep -n '^WATCHDOG_INTERVAL=' /etc/nvr/nvr.conf /etc/nvr/conf.d/*.conf
    => ^ = the line must START with this, so # comments drop out
    => the = at the end drops WATCHDOG_INTERVAL_MAX (its next char is _)
    => *.conf = only files ending in .conf, and the shell lists them
       in name order: 10-, 20-, 50-, 60- = the loader's order
    => the quotes just stop the shell from touching the ^ and =
    => /etc/nvr/conf.d/20-analytics.conf:6:WATCHDOG_INTERVAL=60
       /etc/nvr/conf.d/50-site.conf:5:WATCHDOG_INTERVAL=300
       /etc/nvr/conf.d/60-tuning.conf:8:WATCHDOG_INTERVAL=15  <- last
    => (the files are regenerated each run: your numbers will differ)

## 3 ACT
SAY: "The last surviving assignment wins, so that file, that line, that
      value is the answer."
  $ answer "file=/etc/nvr/conf.d/60-tuning.conf line=8 value=15"
    => use YOUR last line: file:LINE:WATCHDOG_INTERVAL=VALUE

## 4 VERIFY
SAY: "Double-check by looking at that file with line numbers."
  $ cat -n /etc/nvr/conf.d/60-tuning.conf
    => -n = number every line
    =>      8  WATCHDOG_INTERVAL=15
  $ check

TRAP
  - `WATCHDOG_INTERVAL_MAX` and `WATCHDOG_INTERVAL_OVERRIDE` match a plain
    grep (search for `^WATCHDOG_INTERVAL=` instead).
  - A commented default (#) is not an assignment.
  - `.dpkg-old` / `.disabled` files are never loaded.
  - The first (or last) hit in a recursive grep is not the winner: -r
    walks files in disk order, not the loader's order.

DO IT BETTER
  - Read the README before you search: the loader's RULES decide the
    answer, not grep.
  - Throw out what the loader ignores: comments, look-alike keys,
    backups, anything not *.conf.
  - The LAST loaded assignment wins; look at that one line to confirm.
