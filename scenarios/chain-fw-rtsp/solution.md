# chain-fw-rtsp: camera1 'reconnecting' after the compliance change

WEAK SPOT    "Ping works, the web page works, so the network is fine."
             Ping and port 80 are not port 554. A TIMEOUT on one port
             while others answer = a silent DROP somewhere. Look at the
             box's OWN firewall before the switch or the camera.
LOCAL-FIRST  The drop is in this box's OUTPUT chain. nc proves it, the
             iptables packet counters point at the exact rule.

THE SHORT FORMS (this is all you type)
  systemctl --failed                   what died (and what to ignore)
  sudo journalctl -u nvr-recorder | tail     what the recorder hits
  ping -c 3 10.50.1.31                 is the camera reachable at all
  nc -zv -w 3 10.50.1.31 554           does THIS port connect
  sudo iptables -L -n -v               the firewall, with counters
  sudo iptables -L CAM-EGRESS -n -v --line-numbers    one chain, numbered
  systemctl status netfilter-persistent    where the rules come from
  sudo grep -n 554 /etc/iptables/rules.v4  the line to remove
  sudo nano /etc/iptables/rules.v4     delete ONLY that line
  sudo iptables-restore --test /etc/iptables/rules.v4     syntax check
  sudo systemctl restart netfilter-persistent   load the file, live

## 1 OBSERVE
SAY: "No alerts from one camera. I'll sweep the box first, then ask
      the recorder what it actually hits."
  $ systemctl --failed
    => fwupd-refresh.service  failed   (firmware metadata refresh)
    => it can't resolve its update server: offline box, not our
       camera. Noted and ignored.
  $ systemctl status nvr-recorder
    => Active: active (running): the software is up
  $ sudo journalctl -u nvr-recorder | tail
    => -u = only this unit's log   tail = the last 10 lines
    => camera1: RTSP connect to 10.50.1.31:554 timed out after 3s,
       reconnecting
    => camera2: RTSP connect to 10.50.1.32:554 timed out after 3s, ...
  $ cat ~/install-sheet.txt
    => camera2  10.50.1.32  REMOVED 2026-08 ... expect "reconnecting"
    => camera2 is the red herring: it is gone. camera1 is the ticket.

## 2 NARROW
SAY: "The recorder never gets a connection on 554. Is it the camera,
      the path, or this port only?"
  $ ping -c 3 10.50.1.31
    => -c 3 = send 3 pings then stop
    => 3 packets transmitted, 3 received, 0% packet loss
  $ curl http://10.50.1.31/
    => camera1 - RTSP relay OK - stream 1080p30   (port 80 works)
  $ nc -zv -w 3 10.50.1.31 554
    => -z = just connect, send nothing   -v = say what happened
    => -w 3 = give up after 3 seconds
    => nc: connect to 10.50.1.31 port 554 (tcp) timed out
SAY: "Same camera, port 80 answers, port 554 times out. Not 'refused'
      (that would be the camera saying no): nothing came back at all.
      Something drops it, and the first place is this box's firewall."
  $ sudo iptables -L -n -v
    => -L = list the rules   -n = numbers, not names (faster)
    => -v = show packet counters (pkts, bytes) per rule
    => Chain OUTPUT (policy ACCEPT ...)
    =>    30  1882 CAM-EGRESS  0  --  *  *  0.0.0.0/0  10.50.1.0/24
    => everything this box sends to the camera VLAN jumps to CAM-EGRESS
    => Chain CAM-EGRESS
    =>     0     0 DROP  6  --  ...  tcp dpt:21
    =>     0     0 DROP  6  --  ...  tcp dpt:23
    =>    17  1020 DROP  6  --  ...  tcp dpt:554    <- counter climbing
    => prot 6 = tcp, 17 = udp;  dpt = destination port
  $ sudo iptables -L CAM-EGRESS -n -v --line-numbers
    => --line-numbers = number each rule (what -D N would delete)
    => 4    17  1020 DROP  6  --  ...  tcp dpt:554
SAY: "Rule 4 in CAM-EGRESS drops RTSP to every camera. Where does it
      come from at boot? If I only delete it live, it comes back."
  $ systemctl status netfilter-persistent
    => Active: active (exited): a one-shot that loads rules at boot
  $ systemctl cat netfilter-persistent
    => ExecStart=/usr/sbin/netfilter-persistent start
  $ sudo grep -n 554 /etc/iptables/rules.v4
    => -n = print the line number
    => 15:-A CAM-EGRESS -p tcp --dport 554 -j DROP
    => (the file is 0640 root: without sudo, "Permission denied")

## 3 ACT
SAY: "I'll delete that one line in the boot file, check the file still
      loads, then load it, so the live rules and the boot rules match.
      Everything else in the baseline stays."
  $ sudo nano /etc/iptables/rules.v4
    => delete the line: -A CAM-EGRESS -p tcp --dport 554 -j DROP
    => save (Ctrl+O, Enter), quit (Ctrl+X)
  $ sudo iptables-restore --test /etc/iptables/rules.v4
    => --test = parse the file, change nothing (no output = it loads)
  $ sudo systemctl restart netfilter-persistent
    => re-runs the loader: the live firewall now = the file
  Same result the other way round: sudo iptables -D CAM-EGRESS 4
  (-D = delete rule number 4), then sudo netfilter-persistent save
  (writes the live rules to rules.v4; it drops the file's comments)

## 4 VERIFY
SAY: "Proof: the port, then what the RECORDER gets, then that the rest
      of the baseline is still there."
  $ sudo iptables -L CAM-EGRESS -n --line-numbers
    => 1 DROP tcp dpt:21   2 DROP tcp dpt:23   3 DROP udp dpt:69
    => 4 DROP udp dpt:161      (554 gone, the other four kept)
  $ nc -zv -w 3 10.50.1.31 554
    => Connection to 10.50.1.31 554 port [tcp/rtsp] succeeded!
  $ sudo journalctl -u nvr-recorder | tail -3
    => tail -3 = only the last 3 lines
    => camera1: DESCRIBE rtsp://10.50.1.31:554/... -> RTSP/1.0 200 OK,
       stream up
    => camera2: ... timed out  (still: it is removed, not our fault)
  $ nc -zv -w 3 10.50.1.31 23
    => timed out: telnet to the cameras is still blocked, as audited
  $ check

TRAP
  - "Ping works, so it's the camera/recorder": ping is ICMP, not
    tcp/554. Test the exact port the service uses.
  - Flushing the firewall (iptables -F) or disabling netfilter-persistent:
    RTSP works, and you just removed an audited security baseline.
  - An ACCEPT-all for 10.50.1.0/24 ahead of CAM-EGRESS: opens telnet
    and ftp to every camera too.
  - Deleting the rule live only: rules.v4 puts it back at the next boot.
  - Editing rules.v4 only: nothing reads it until the unit reloads.
  - Chasing camera2 or the failed fwupd-refresh: one is a removed
    camera, the other is a firmware check that can't reach the internet.

DO IT BETTER
  - Timeout = dropped, refused = the far end said no, 401/404 = the
    application answered. nc -zv tells you which in one second.
  - iptables -L -n -v counters: send the traffic, see which rule's
    count goes up. That is the rule, no guessing.
  - Fix the source (rules.v4), then load it: live and boot agree.
  - ESCALATE / TELL THE CUSTOMER: "SEC-114 rule CAM-EGRESS tcp/554 DROP
    blocked camera RTSP to the recorder. Removed that one rule on
    edge-nvr-03 (live + /etc/iptables/rules.v4); ftp/telnet/tftp/snmp
    blocks kept. Please update the baseline so the next push does not
    re-add it."
