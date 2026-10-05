# inode-full: "No space left on device" but df shows plenty free

WEAK SPOT    `df -h` counts BLOCKS. A filesystem also has a fixed number
             of INODES (one per file/dir), and thousands of tiny files
             can use them all up while the disk looks empty. `df -i` is
             the second half of "is the disk full?".
LOCAL-FIRST  the error is on this box's own filesystem; nothing to do with
             the network.

THE SHORT FORMS (this is all you type)
  df -h /var/spool/frames             BLOCKS: plenty of space?
  df -i /var/spool/frames             INODES: IFree 0 = the fault
  sudo du --inodes /var/spool/frames  which folders hold the inodes
  sudo find /var/spool/frames -type f -mtime +3 | wc -l
                                      how many are older than 3 days
  sudo find /var/spool/frames -mtime +3 -delete
                                      delete by age (look first)
  touch /var/spool/frames/x           can a new file be created?

## 1 OBSERVE
SAY: "'No space left' but monitoring says 80% free. That means it is not
      blocks. Let me see both views of the volume."
  $ sudo journalctl -u frame-grabber -n 5
    => -u = only this unit's lines   -n 5 = only the last 5 lines
    => cannot write /var/spool/frames/.../cam4-142425.jpg:
       [Errno 28] No space left on device
  $ df -h /var/spool/frames
    => -h = human sizes (M, G)
    => tmpfs  64M  12M  53M  19%: plenty of space
  $ df -i /var/spool/frames
    => -i = count inodes instead of space. Every file and folder uses
       one inode, and a filesystem only has a fixed number of them.
    => Inodes 3000  IUsed 3000  IFree 0  IUse% 100%   <- the fault
  $ touch /var/spool/frames/x
    => touch = create an empty file
    => "No space left on device", even for a zero-byte file

## 2 NARROW
SAY: "Out of inodes on /var/spool/frames. Who is holding them, how old is
      it, and what must NOT be deleted?"
  $ ls /var/spool/frames
    => one folder per day, from ~13 days ago up to today
  $ sudo du --inodes /var/spool/frames
    => --inodes = count files in each folder, not their size
    => 289 in each old day folder (2026-09-13 ... -20)
    => 109-144 in the last few days, 3000 in total
  $ ls -l /var/spool/frames/2026-09-18 | head -4
    => use one of YOUR old folder names
    => -l = long listing (size, date)   head -4 = first 4 lines only
    => -rw-r--r-- 1 nvr nvr 1404 Sep 18 00:11 cam1-001155.jpg
    => tiny 1.4K thumbnails: a pile of small files, not big ones
  $ sudo find /var/spool/frames -type f | wc -l
    => -type f = files only (not folders)   wc -l = count the lines
    => 2985
  $ sudo find /var/spool/frames -type f -mtime +3 | wc -l
    => -mtime +3 = last changed MORE than 3 days ago
    => 2485 of them: that is the pile
SAY: "Today's and yesterday's frames are the incident-review data. I
      delete by age, never the whole folder."

## 3 ACT
SAY: "Look at what would go, delete everything older than three days,
      leave the last days, and add a daily job so it can't pile up
      again."
  $ sudo find /var/spool/frames -mtime +3 | head -3
    => the dry run: same search, only LISTS what it matches
    => /var/spool/frames/2026-09-12
    => /var/spool/frames/2026-09-12/cam1-183155.jpg
  $ sudo find /var/spool/frames -mtime +3 -delete
    => -delete = delete everything it matched (no undo)
  $ df -i /var/spool/frames
    => IUsed 506  IFree 2494  IUse% 17%
  $ ls /var/spool/frames
    => only 2026-09-21 ... today are left

  retention (bonus): a daily job, so it can't fill up again
  $ sudo nano /etc/cron.daily/frames-retention
    => type these two lines, save (Ctrl+O, Enter), exit (Ctrl+X):
       #!/bin/sh
       find /var/spool/frames -mindepth 1 -mtime +3 -delete
    => -mindepth 1 = never delete /var/spool/frames itself
  $ sudo chmod 755 /etc/cron.daily/frames-retention
    => cron only runs it if it has the execute bit
  (a systemd timer or a tmpfiles.d age rule work too; the cause is
  thumbnails with no retention at all)

## 4 VERIFY
SAY: "Inodes are back, a new file can be created, the service writes
      again, and the recent frames are still there."
  $ df -i /var/spool/frames
    => IUse% well under 80
  $ touch /var/spool/frames/x
    => no error this time
  $ rm /var/spool/frames/x
    => clean up the test file
  $ ls -lt /var/spool/frames/2026-09-25 | head -4
    => use TODAY's folder name   -t = newest first
    => cam1-142522.jpg, cam4-142521.jpg ... with the time right now:
       a new one every second
  $ sudo journalctl -u frame-grabber -n 3
    => the last error's time is BEFORE your fix: no new ones

TRAP
  - `rm -rf /var/spool/frames/*` frees every inode and destroys the last
    24 h of frames the ticket said to keep.
  - Deleting a single old folder frees ~290 of 3000 inodes: full again
    in minutes.
  - Restarting the grabber changes nothing (the service is fine, the
    filesystem is out of inodes).
  - Stopping it silences the error and the thumbnails.
  - Do not go looking for a "bigger disk": blocks are not the limit here,
    `df -h` will keep saying 19%.

DO IT BETTER
  - "No space left" with free blocks: run `df -i`, the second half of
    "is the disk full?".
  - Count files, not size: the count is what matters.
  - Delete by age, never the whole folder, and look at the list first.
  - Fix the cause (no retention at all) with a daily retention job.
