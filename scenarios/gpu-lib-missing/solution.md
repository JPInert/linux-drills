# gpu-lib-missing: the CUDA update left libcudart.so.12 pointing at nothing

WEAK SPOT    "the file is there" vs "the name resolves". `ls` happily
             lists a dangling symlink (a link whose target is gone);
             only opening it tells the truth: `ls` the TARGET and see
             "No such file". Also: the loader cache (`ldconfig -p`) is a
             snapshot and can say "present" for a name that no longer
             leads anywhere.
LOCAL-FIRST  pure local. The box has no route to the mirror on purpose:
             you cannot `apt install` your way out, you have to read what
             is on the disk.

THE SHORT FORMS (this is all you type)
  sudo journalctl -u analytics -n 20  why it fell back (needs sudo)
  ls -l /usr/local/cuda/lib64/        what the link points at (->)
  ls -l /usr/local/cuda/lib64/libcudart.so.12.4.99
                                      does the target EXIST?
  sudo ldconfig -p | grep cudart      the loader cache (can be STALE)
  nvidia-smi                          CUDA Version the driver supports
  cd /usr/local/cuda/lib64            go to the library folder
  sudo ln -sf libcudart.so.12.2.140 libcudart.so.12
                                      repoint the link
  sudo ldconfig                       rebuild the loader links/cache
  sudo systemctl restart analytics    CUDA only initialises at start

## 1 OBSERVE
SAY: "Slow analytics and a flat GPU. Is the GPU itself alive, and what
      does the service say when it falls back?"
  $ nvidia-smi
    => driver answers, GPU idle, "No running processes found"
  $ sudo journalctl -u analytics -n 20
    => -u = only this unit (service). -n 20 = the last 20 lines
    => WARN detect: CUDA init failed: error while loading shared
       libraries: libcudart.so.12: cannot open shared object file: No
       such file or directory
    => WARN detect: falling back to CPU inference
    => tech is not in the systemd-journal group: without sudo it says
       "No journal files were opened"
  $ tail -1 /var/log/analytics/detect.log
    => tail -1 = the last line
    => cams=4 fps=2.0 device=cpu

## 2 NARROW
SAY: "A CUDA runtime library cannot be opened. It lives in
      /usr/local/cuda/lib64. Does it exist, and does the name RESOLVE?"
  $ ls -l /usr/local/cuda/lib64/
    => -l = long list: a link shows as  NAME -> TARGET
    => libcudart.so.12 -> libcudart.so.12.4.99
    => libcudart.so.12.2.140   729088 bytes: the real, installed file
    => no libcudart.so.12.4.99 in the list
  $ ls -l /usr/local/cuda/lib64/libcudart.so.12.4.99
    => No such file or directory: the arrow points at nothing
  $ sudo ldconfig -p | grep cudart
    => ldconfig lives in /usr/sbin, so plain `ldconfig` is "command not
       found" for tech; sudo finds it. -p = print the loader's cache
    => libcudart.so.12 (libc6,x86-64) => .../lib64/libcudart.so.12
    => the cache still lists it: STALE, the reason it "should" work
  $ nvidia-smi
    => top line: CUDA Version: 12.2, so 12.2.140 is what fits
SAY: "The update flipped the link to 12.4.99 but that file never arrived.
      12.2.140 is installed and is what the driver supports. I'll point
      the name back at what is on the disk."

## 3 ACT
SAY: "Repoint the link at the installed file, rebuild the loader
      links/cache, and restart: the daemon only initialises CUDA at
      start."
  $ cd /usr/local/cuda/lib64
  $ sudo ln -sf libcudart.so.12.2.140 libcudart.so.12
    => ln = make a link. -s = a symbolic link (a pointer, not a copy)
    => -f = replace the link that is already there
    => first name = what it points AT, second name = the link itself
  $ sudo ldconfig
    => rebuilds the loader cache. On its own this ALSO re-creates the
       link: the real library carries its name (SONAME) inside it
  $ sudo systemctl restart analytics

## 4 VERIFY
SAY: "Confirming the name resolves, the cache agrees, and the service
      itself is the process on the GPU."
  $ ls -l libcudart*
    => (still in the lib64 folder from the cd above)
    => libcudart.so.12 -> libcudart.so.12.2.140
    => libcudart.so.12.2.140
  $ nvidia-smi
    => Processes: ... /opt/analytics/analytics.py   1874MiB
  $ sudo journalctl -u analytics -n 3
    => INFO detect: CUDA device 0 initialised: NVIDIA RTX A2000 12GB,
       using GPU inference (TensorRT)
  $ check

TRAP
  - `touch libcudart.so.12.4.99` makes the error go away with an EMPTY
    file pretending to be a newer runtime.
  - Adding LD_LIBRARY_PATH for the service changes nothing: the directory
    is already searched, the name in it is dead.
  - Fixing the link without restarting leaves the running daemon on its
    CPU fallback (it decides at start).
  - "Reinstall the driver / CUDA" cannot work here: no mirror, and
    nvidia-smi already answers.

DO IT BETTER
  - "the file is there" is not "the name resolves": follow the arrow
    and `ls -l` the target itself.
  - Don't trust the loader cache: `sudo ldconfig -p` is a snapshot and
    can be STALE.
  - Read what is on the disk and point the name back at it; you cannot
    `apt install` your way out.
  - Restart after the fix: the daemon only initialises CUDA at start.
