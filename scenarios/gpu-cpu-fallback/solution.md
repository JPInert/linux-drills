# gpu-cpu-fallback: detections lag ~10x, the model fell back to CPU

WEAK SPOT    "slow" is not "network". A model that quietly fell back to
             CPU looks exactly like a lag problem from the wall display;
             the site already burned a cable swap on it.
             Also: a unit's environment can come from three places
             (Environment=, EnvironmentFile=, drop-ins). `systemctl cat`
             shows all of them; a look at one of them can mislead.
LOCAL-FIRST  nothing here leaves the box. ping/traceroute would prove
             nothing.

THE SHORT FORMS (this is all you type)
  nvidia-smi                          is the model actually on the GPU?
  sudo journalctl -u analytics -n 20  why it fell back (needs sudo)
  tail -3 /var/log/analytics/detect.log     fps=... device=cpu or cuda:0
  systemctl cat analytics             unit + drop-in + EnvironmentFile=
  cat /etc/default/analytics          the file that sets the variable
  sudo nano /etc/default/analytics    delete the leftover line
  sudo systemctl restart analytics    re-read the environment

## 1 OBSERVE
SAY: "Video is smooth, detections are slow. Before I blame the network:
      is the model actually on the GPU?"
  $ systemctl status analytics
    => active (running): it is not down
    => Main PID: 127 (python3)  (yours will differ)
  $ nvidia-smi
    => driver answers: 0MiB / 12288MiB used, GPU-Util 0%
    => Processes table: "No running processes found"
  $ sudo journalctl -u analytics -n 20
    => -u = only this unit (service). -n 20 = the last 20 lines
    => WARN detect: CUDA init failed: CUDA_ERROR_NO_DEVICE: no
       CUDA-capable device is detected (CUDA_VISIBLE_DEVICES='-1')
    => WARN detect: falling back to CPU inference
       (expect ~1/12 throughput)
    => tech is not in the systemd-journal group: without sudo it says
       "No journal files were opened"
  $ tail -3 /var/log/analytics/detect.log
    => tail -3 = the last 3 lines
    => cams=4 fps=2.0 device=cpu
    => healthy is fps=24.0 device=cuda:0

## 2 NARROW
SAY: "The GPU and driver are fine. The service is hiding the GPU from
      itself with CUDA_VISIBLE_DEVICES=-1. Who sets that?"
  $ sudo grep DEVICE /etc/analytics/analytics.conf
    => readable by root only, hence sudo
    => DEVICE=cuda: the config is right
  $ systemctl cat analytics
    => prints the unit file AND every drop-in, each with its path
    => EnvironmentFile=-/etc/default/analytics   <- load vars from here
    => 10-tuning.conf: Environment=CUDA_DEVICE_ORDER=PCI_BUS_ID
       (harmless)
  $ cat /etc/default/analytics
    => # 2026-08-19 bench test on the GPU-less lab unit
    => CUDA_VISIBLE_DEVICES=-1      <- the leftover

  optional proof of what the RUNNING process got (PID from status):
  $ sudo cat /proc/127/environ | tr '\0' '\n'
    => /proc/PID/environ = that process's environment, as the kernel
       holds it. The entries are glued together with invisible zero
       bytes; tr '\0' '\n' swaps each zero byte for a new line
    => CUDA_VISIBLE_DEVICES=-1

## 3 ACT
SAY: "That line belongs to a GPU-less lab unit. I'll remove it, then
      restart: a running process never re-reads its environment."
  $ sudo nano /etc/default/analytics
    => go to the CUDA_VISIBLE_DEVICES=-1 line, Ctrl-K cuts it
    => Ctrl-O then Enter saves, Ctrl-X quits (or set it to =0)
    => or in one line, no editor:
  $ sudo sed -i '/^CUDA_VISIBLE_DEVICES=/d' /etc/default/analytics
    => -i = edit the file in place
    => /^CUDA_VISIBLE_DEVICES=/d = delete the line that starts with it
  $ sudo systemctl restart analytics

## 4 VERIFY
SAY: "Confirming the service itself is now the process on the GPU."
  $ nvidia-smi
    => Processes: ... /opt/analytics/analytics.py   1874MiB
    => GPU-Util above 0%
  $ sudo journalctl -u analytics -n 3
    => INFO detect: CUDA device 0 initialised: NVIDIA RTX A2000 12GB,
       using GPU inference (TensorRT)
  $ tail -2 /var/log/analytics/detect.log
    => fps=24.0 device=cuda:0
  $ systemctl is-active analytics
    => active
  $ check

TRAP
  - An `Environment=CUDA_VISIBLE_DEVICES=0` in a drop-in LOSES: systemd
    applies EnvironmentFile= after Environment=, so the file wins. Use
    `UnsetEnvironment=CUDA_VISIBLE_DEVICES` in a drop-in, or fix the file.
  - `systemctl show analytics -p Environment` looks clean: it lists
    only Environment= lines (CUDA_DEVICE_ORDER), never the file's.
  - `DEVICE=cpu` in analytics.conf just picks the slow path on purpose
    (the warning now blames DEVICE=cpu).
  - Editing the file without a restart changes nothing for the running
    process.
  - Restarting without editing changes nothing for the file.
  - "Reinstall the driver" is a non-starter: nvidia-smi already answers.

DO IT BETTER
  - "slow" is not "network": check nvidia-smi and the journal before
    blaming the cable.
  - Find every place the environment comes from (systemctl cat), not
    only one piece of it.
  - Read /proc/PID/environ for proof of what the running process really
    got.
  - Edit AND restart: a running process never re-reads its environment.
