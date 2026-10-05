# Break-fix cheat sheet (one page)

**Say it out loud:** OBSERVE ("what do I see?") → NARROW ("which part?") → ACT ("smallest fix") → VERIFY ("prove it").
**Local first:** the box before the network. `systemctl`, `df`, `ss`, `top` before `ping`, `traceroute`, `dig`.

## First 60 seconds on any box
```
whoami; hostname; uptime              who/where/how long up
systemctl --failed                    what is already broken
df -h ; df -i                         space, then inodes
top   (then P = CPU, M = memory)      who is hogging
ss -ltnp                              what is listening (sudo for other users' processes)
sudo journalctl -p err -b --no-pager | tail -20   recent errors
```

## By job
| Question | Command | Notes |
|---|---|---|
| **Which drive/filesystem is full?** | `df -h` | one line per FILESYSTEM. Look for 100%. `-x tmpfs` can hide the culprit |
| Out of inodes? (space free but "No space left") | `df -i` | many tiny files. `find DIR -type f \| wc -l` |
| **What is filling it?** | `sudo du -sh /var/* \| sort -h` then go one level deeper: `sudo du -sh /var/log/*` | `-s` one total per folder · `-h` human sizes · `sort -h` puts the biggest last |
| Biggest files fast | `sudo find /var -xdev -type f -size +100M -exec ls -lh {} +` | |
| df says full, du says small | `sudo lsof +L1` | deleted-but-still-open file. Restart the holder or `: > /proc/PID/fd/N` |
| Empty a log a daemon holds open | `sudo truncate -s0 FILE` | **not** `rm` (frees nothing) |
| Rotate | `logrotate -d /etc/logrotate.d/X` (dry run), `-f` force | `copytruncate` for daemons that keep the file open |
| **What is using this port?** | `sudo ss -tlnp \| grep 8080` or `sudo lsof -i :8080` | `-t` TCP `-l` listening `-n` numbers `-p` program name. Without sudo you don't see other users' programs |
| **Stop a process** | `kill PID` (TERM) → check → `kill -9 PID` | then `pkill NAME` / `killall NAME` by name |
| Find a process | `ps aux \| grep NAME` | columns: USER, PID, %CPU, %MEM … COMMAND. The grep line itself also shows up; ignore it |
| Who is hogging CPU / memory | `top` then `P` (CPU) or `M` (memory), `q` quits | `kill` on a service that respawns is pointless: `systemctl stop` |
| **Is the service OK?** | `systemctl status X` · `is-active X` · `is-enabled X` | |
| Start now + at boot | `sudo systemctl enable --now X` | |
| **Why did it fail?** | `sudo journalctl -u X` then `sudo journalctl -u X \| tail -20` · `-f` to follow live | plain `journalctl` shows a normal user little or nothing: use sudo. `status=203/EXEC` = bad ExecStart / missing binary |
| Unit file edited | `sudo systemctl daemon-reload` then restart | forgetting this is the classic |
| What does the unit really run / read? | `systemctl cat X` | shows the unit AND any drop-in overrides; look at ExecStart, User, EnvironmentFile |
| Masked? | `sudo systemctl unmask X` | |
| **Is the GPU alive?** | `nvidia-smi` · `nvidia-smi -L` · `lspci \| grep -i nvidia` | process table empty = nothing is using the GPU |
| Who is using the GPU | `nvidia-smi`, read the Processes table at the bottom | empty table + slow app = it fell back to CPU |
| Service falling back to CPU | `sudo journalctl -u X \| grep -i cuda` · `systemctl cat X` then `cat` the EnvironmentFile it names | `CUDA_VISIBLE_DEVICES`, missing `libcudart`, driver mismatch |
| Shared library missing | `sudo ldconfig -p \| grep cuda` · `ls -l LIBPATH` · `readlink -f LIBPATH` | dangling symlink after an update |
| GPU memory full (OOM, falls back to CPU) | `nvidia-smi` (Memory-Usage + process table) → `systemctl status PID` (who owns it) | a unit with `Restart=always` returns after `kill`: `sudo systemctl disable --now UNIT` |
| Local LLM (ollama) | `ollama ps` (loaded, on GPU?) · `ollama list` · `curl -s localhost:11434/api/ps` · `systemctl cat ollama` | `ollama stop MODEL` unloads now; the service still starts at boot |
| **What is my address / route?** | `ip -br a` · `ip r` · `ip route get IP` | `ip a` / `ip r`, not ifconfig / route |
| Walk the path | `ping -c2 GATEWAY` → `ping -c2 TARGET` → `traceroute -n TARGET` | stop at the first hop that stops answering; note WHO replies |
| Set / fix a route | `sudo ip route replace default via GW` | `replace`, not `add` (twice = two defaults) |
| Fix an address | `sudo ip addr flush dev eth0; sudo ip addr add A.B.C.D/24 dev eth0; sudo ip route add default via GW` | flushing removes the default route |
| **DNS** | `cat /etc/resolv.conf` · `dig @SERVER name +short` · `getent hosts name` | dig asks a server; getent/ping use the system resolver |
| Is a port open remotely? | `nc -zv HOST PORT` · `curl -sv HOST:PORT` | |
| **SSH not working** | `sudo ss -ltnp \| grep sshd` · `sudo sshd -T \| grep -i ^port` · `sudo sshd -t` · `systemctl status ssh` | `sshd -T` = EFFECTIVE config (drop-ins in `sshd_config.d/`). Test config BEFORE restart |
| **Permissions** | `ls -l FILE` · `ls -ld DIR` · `id` · `namei -l /path/to/file` | service user needs `x` on every directory in the path and `r` on the file |
| Fix them (least privilege) | `sudo chgrp svc FILE; sudo chmod 640 FILE` | never `chmod 777` |
| Search logs | `grep -ri ERROR /var/log/X \| tail` · `tail -f FILE` · `sudo journalctl --since '1 hour ago'` | |
| **adb (Android/SoC device; off by default)** | `adb devices -l` · `adb kill-server && adb start-server` · `adb connect IP:5555` | states: device / offline / unauthorized / no permissions |
| adb evidence | `adb logcat -d \| grep -i fatal` · `adb logcat -b radio -d` · `adb shell getprop gsm.sim.state` · `adb shell dumpsys telephony.registry` | |
| adb fixes | `adb shell pm grant PKG android.permission.X` · `adb shell am force-stop PKG` · `adb shell settings get global airplane_mode_on` · `adb shell svc data enable` | |

## Topics a container can't fake (say these, don't drill them)
| Topic | Look | Fix / say |
|---|---|---|
| **AWS SSM** (remote shell on cloud-managed boxes) | `systemctl status amazon-ssm-agent` · `sudo journalctl -u amazon-ssm-agent -n 50` · logs `/var/log/amazon/ssm/` | agent needs outbound 443 to `ssm.<region>.amazonaws.com`, a sane CLOCK (TLS), an IAM role/activation. Box "offline in SSM" = agent down, no egress, or clock skew |
| **Grafana shows no data** | is the exporter up? `systemctl status node_exporter` · `curl -s localhost:9100/metrics \| head` · `ss -ltnp` | walk it: exporter → scrape (Prometheus targets page) → dashboard query/time range. Flat line = source down, not "no problem" |
| **Clock** (breaks TLS, SSM, logs) | `timedatectl` · `chronyc tracking` | `sudo timedatectl set-ntp true`. "certificate not yet valid" = clock |
| **Docker** | `sudo docker ps -a` · `sudo docker logs NAME` · `sudo docker inspect NAME \| grep -i oom` | STATUS `Exited (137)` = killed (often out of memory). GPU in a container needs `--gpus all` / `runtime: nvidia` |
| **VLAN** | `ip -d link show` · `bridge vlan` · switch: `show vlan brief`, `show int trunk` | camera on the wrong access VLAN = no DHCP lease. Tagged vs untagged is the usual miss |
| **DHCP** | `ip -br a` (169.254.x = no lease) · `sudo journalctl -u NetworkManager \| grep -i dhcp` · `sudo dhclient -v eth0` | no lease: wrong VLAN, no helper/relay, scope full. Static installs: reserve by MAC on the server |
| **NIC config that survives reboot** | `nmcli con show` · `cat /etc/netplan/*.yaml` · `/etc/network/interfaces` | `ip addr add` is gone at reboot: persist with `nmcli con mod` or netplan `apply` |
| **NAT / PAT** | `sudo iptables -t nat -L -n -v` · `sudo nft list ruleset` | port forward = DNAT on the edge; many-to-one = PAT/masquerade |
| **WiFi (edge devices)** | `iw dev wlan0 link` (signal, bitrate) · `nmcli dev wifi list` (channels, neighbours) | below about -70 dBm is weak; 2.4 GHz channel crowding; roaming drops. Wire it if it streams video |
| **PoE** | switch: `show power inline` | camera boots then drops = over budget or a bad cable; class vs budget |
| **Out-of-band** | IPMI/iDRAC/iLO: `ipmitool -I lanplus -H IP -U user chassis status` · LTE console server | the path you use when the box's own network is what broke. Test it at install, not in the outage |
| **RTSP** | `nc -zv CAM 554` · `curl -v rtsp://CAM:554/PATH` · `ffprobe rtsp://user:pass@CAM/PATH` | 401 = credentials, 404 = stream path, refused = service/port. RTSP sets up; RTP carries the video |
| **A device API** | `curl -sv https://DEV/api/...` · `-H "Authorization: Bearer $T"` · `\| jq .` | 401 = token, 403 = allowed-list/role, 404 = path/version, 5xx = device side, refused/timeout = network/service |

## grep / awk kit (log questions: filter FIRST, then the right field, then count)
| Want | Command |
|---|---|
| Lines containing X, with numbers / file names | `grep -n X FILE` · `grep -rn X DIR` (add `--include='*.conf'`) |
| Whole word only (not X_MAX) / anchored | `grep -w X` · `grep '^X='` |
| Case-insensitive / invert / count | `grep -i` · `grep -v` · `grep -c` |
| Just the matching part | `grep -o 'ip=[0-9.]*'` then `cut -d= -f2` |
| Context around a hit | `grep -B2 -A5 X` · `-C3` |
| Any of several | `grep -E 'error\|fail\|denied'` (or `grep -e a -e b`) |
| A time window (anchor on the line start) | `grep '^2026-09-23 02:' FILE` |
| Compressed / rotated logs | `zgrep X FILE.gz` · `zcat FILE.gz \| grep X` |
| **Top N of anything** | `... \| sort \| uniq -c \| sort -rn \| head` |
| One field of a line | `cut -d' ' -f3` · `awk '{print $3}'` |
| Filter on a field (not "digits anywhere") | `awk '$6 ~ /^5/'` · `awk '$6==404'` · `awk '$1=="2026-09-23" && $2 ~ /^02:/'` |
| Count matching lines | `... \| wc -l` · `awk '$6==404 {n++} END{print n}'` |
| Count per key in awk | `awk '{c[$3]++} END{for(k in c) print c[k], k}' F \| sort -rn` |
| Follow live | `tail -f FILE \| grep --line-buffered X` |
| Files that mention X (names only) | `grep -rl X DIR` · files that do NOT: `grep -rL X DIR` |
| Which config file wins? | read the loader's rules; ordered hits: `for f in a.conf conf.d/*.conf; do grep -Hn '^KEY=' "$f"; done` (last wins) |

## Never (your confusions)
| You reach for | Instead |
|---|---|
| `fdisk` for "disk full" | `fdisk` edits **partition tables**. Full disk = `df -h` then `du` |
| `ldisk`, `lsof` typos | `lsof` = **LiSt Open Files** (`lsof -i :PORT` for ports). `lsblk` = block devices |
| `rfkill` for "kill it" | `rfkill` toggles wifi/bluetooth radios. You want `kill PID` / `systemctl stop` |
| `df` vs `du` | `df` = filesystems (which is full). `du` = directories (what is in it) |
| `ifconfig`, `netstat`, `route`, `arp` | `ip a`, `ss -ltnp`, `ip r`, `ip neigh` |
| `service X start` | `systemctl start X` |
| `kill -9` first | `kill`, check it exited, then `-9` |
| `rm bigfile.log` (daemon has it open) | `truncate -s0 bigfile.log` |
| `ping` first | is the SERVICE / DISK / CONFIG on this box wrong? then the network |
| `chmod 777` | `chown`/`chgrp` + the smallest mode that works |
| restart and hope | read the journal first |

## The drill box
`ticket` · `hint` (progressive) · `check` · `solution` · `timer` · `answer "..."` (diagnose-only tickets).
Container quirks: `free`/`uptime`/`nproc` and `df /` show the HOST; `/etc/resolv.conf` is a Docker mount (`sed -i` fails, use `sudo tee`/`vi`);
`df` lists extra tmpfs lines for /proc and /sys: ignore them.
