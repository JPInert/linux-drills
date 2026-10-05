# gpu-driver-down: nvidia-smi can't talk to the driver,
  analytics fell back to CPU

WEAK SPOT    an outside-in checklist for "the GPU is dead": on the bus
             (lspci) -> kernel modules loaded (lsmod) -> the userspace
             piece that brings the driver up (unit state) -> only THEN
             think about reinstalling.
             Also: fixing the driver stack does not fix its consumer.
             analytics decides CPU vs GPU once, at start.
LOCAL-FIRST  pure local. (The drill's story: on this image the
             persistence daemon is what brings the driver up. On a stock
             box a dead persistenced mostly makes the first CUDA call
             slow; in the field this exact nvidia-smi error is usually
             the module not built for the running kernel: lsmod empty,
             dkms status, Secure Boot. Here lsmod rules that out.)

THE SHORT FORMS (this is all you type)
  nvidia-smi                          does the driver answer?
  lspci | grep -i nvidia              is the card on the bus?
  lsmod | grep nvidia                 are the kernel modules loaded?
  systemctl list-unit-files | grep -i nvidia
                                      which unit, enabled or disabled
  systemctl status nvidia-persistenced
                                      Loaded / Active state
  sudo systemctl enable --now nvidia-persistenced
                                      start it now AND at every reboot
  sudo systemctl restart analytics    it only tries the GPU at start

## 1 OBSERVE
SAY: "nvidia-smi errors instead of printing its table. Is the card even
      there, and is the kernel side loaded?"
  $ nvidia-smi
    => NVIDIA-SMI has failed because it couldn't communicate with the
       NVIDIA driver. Make sure that the latest NVIDIA driver is
       installed and running.
  $ lspci | grep -i nvidia
    => lspci = list the PCI hardware. grep -i = match any upper/lower
       case
    => 01:00.0 VGA compatible controller: NVIDIA Corporation GA106
       [RTX A2000 12GB]: the card is on the bus
  $ lsmod | grep nvidia
    => lsmod = list the kernel modules (drivers) that are loaded
    => nvidia, nvidia_uvm, nvidia_modeset, nvidia_drm: loaded, so not a
       missing module
  $ sudo journalctl -u analytics -n 20
    => -u = only this unit (service). -n 20 = the last 20 lines
    => WARN detect: CUDA init failed: CUDA_ERROR_SYSTEM_DRIVER_MISMATCH
    => WARN detect: falling back to CPU inference
    => tech is not in the systemd-journal group: without sudo it says
       "No journal files were opened"
SAY: "Hardware present, modules loaded, driver not answering: the
      userspace piece that brings it up must not be running."

## 2 NARROW
SAY: "Which unit is that, and what state is it in?"
  $ systemctl list-unit-files | grep -i nvidia
    => list-unit-files = every unit installed, and whether it starts
       at boot
    => nvidia-persistenced.service   disabled   enabled
    => after the name: 1st word = state now (disabled: will NOT start
       at boot), 2nd = vendor preset (enabled: it was MEANT to start)
  $ systemctl status nvidia-persistenced
    => Loaded: ... disabled; preset: enabled
    => Active: inactive (dead)
  $ sudo journalctl -u nvidia-persistenced
    => -- No entries --
    => never ran since the reboot
SAY: "The maintenance re-applied vendor defaults and this came back
      disabled. Start it now AND enable it, or the next reboot repeats
      this."

## 3 ACT
SAY: "Bring the driver up and make it permanent, then restart analytics:
      it only tries the GPU when it starts."
  $ sudo systemctl enable --now nvidia-persistenced
    => enable = start it at every boot. --now = and start it right now
    => Created symlink ... multi-user.target.wants/...
  $ nvidia-smi
    => the table is back, but "No running processes found": analytics is
       still on CPU
  $ sudo systemctl restart analytics

## 4 VERIFY
SAY: "Confirming the driver answers, the unit survives a reboot, and the
      analytics service is the process on the GPU."
  $ systemctl status nvidia-persistenced
    => Loaded: ... enabled; preset: enabled     <- survives a reboot
    => Active: active (running)                 <- running now
  $ nvidia-smi
    => Processes: ... /opt/analytics/analytics.py   1874MiB
  $ sudo journalctl -u analytics -n 3
    => INFO detect: CUDA device 0 initialised: NVIDIA RTX A2000 12GB,
       using GPU inference (TensorRT)
  $ check

TRAP
  - `systemctl restart analytics` first just falls back again: the driver
    underneath is still down.
  - `systemctl start` without `enable` is fixed until the next reboot,
    then it is this ticket again.
  - Fixing the driver without restarting analytics leaves nvidia-smi
    green and the GPU idle: "No running processes found".
  - Running `nvidia-persistenced` by hand works today and nothing brings
    it back after a reboot.
  - `modprobe nvidia` does nothing here: lsmod already showed the module
    loaded.
  - "Reinstall the driver" is a non-starter with no package mirror, and
    the driver was never missing.

DO IT BETTER
  - Work outside-in: lspci -> lsmod -> unit state -> only THEN think
    about reinstalling.
  - `enable --now`, not `start`: fixed today AND after the next reboot.
  - Fixing the driver stack does not fix its consumer: restart analytics,
    then verify it is the process on the GPU in nvidia-smi.
