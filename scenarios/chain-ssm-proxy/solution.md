# chain-ssm-proxy: SSM "Connection Lost" since the customer's web filter

WEAK SPOT    "The box has the proxy settings" means YOUR SHELL has them.
             systemd services never read /etc/environment or profile.d,
             so a service needs its own Environment= in a drop-in.
LOCAL-FIRST  It smells like AWS or the firewall. It is local: the agent
             process was never told about the proxy.

THE SHORT FORMS (this is all you type)
  systemctl --failed                 anything dead? (sweep)
  sudo journalctl -p err -b | tail -20     errors since boot (sweep)
  systemctl status amazon-ssm-agent  running? since when?
  sudo tail -20 /var/log/amazon/ssm/amazon-ssm-agent.log   its errors
  sudo grep -m1 "i/o timeout" /var/log/amazon/ssm/amazon-ssm-agent.log
  cat ~/SITE-NOTES.txt               what changed at this site
  env | grep -i proxy                the proxy YOUR shell has
  sudo journalctl -u amazon-ssm-agent | grep -i proxy   what IT has
  sudo systemctl edit amazon-ssm-agent     add Environment= lines
  sudo systemctl restart amazon-ssm-agent  start it with them
  systemctl cat amazon-ssm-agent     unit + drop-in, as systemd has them

## 1 OBSERVE
SAY: "Tier 1 can't reach the box, but it records video. First the
      sweep: anything failed, and is the remote agent even running?"
  $ systemctl --failed
    => --failed = only units that crashed or failed to start
    => fwupd-refresh.service failed: a firmware-metadata refresh that
       needs the internet. It says "Could not resolve hostname": it
       has nothing to do with remote support. Noted, dismissed.
  $ sudo journalctl -p err -b | tail -20
    => -p err = errors only. -b = since this boot. tail -20 = last 20
    => amazon-ssm-agent ... ERROR [HealthCheck] ... i/o timeout
  $ systemctl status amazon-ssm-agent
    => Active: active (running)   <- "up" is not the same as "online"
  $ sudo tail -20 /var/log/amazon/ssm/amazon-ssm-agent.log
    => the agent's own log file (root-only, hence sudo)
    => ERROR [HealthCheck] ... caused by: Post
       "https://ssm.us-west-2.amazonaws.com/": dial tcp
       52.94.225.18:443: i/o timeout   (same for ec2messages)
    => timeout = packets vanish on the way. Not a refusal, not DNS
  $ sudo grep -m1 "i/o timeout" /var/log/amazon/ssm/amazon-ssm-agent.log
    => -m1 = stop at the first match: WHEN it started
    => yesterday 16:00:07
  $ sudo grep "no such host" /var/log/amazon/ssm/errors.log
    => errors.log = only the ERROR lines, kept longer
    => "lookup ... no such host" 38 days ago: an old DNS outage.
       Different error, long over. The red herring, not this.

## 2 NARROW
SAY: "Something changed yesterday at 16:00. The site notes say what."
  $ cat ~/SITE-NOTES.txt
    => yesterday: web filter live at 16:00, ALL web traffic must go
       through http://10.44.0.10:3128. "Dana set the proxy in
       /etc/environment". Direct HTTPS is dropped.
  $ env | grep -i proxy
    => env = my shell's variables. -i = ignore upper/lower case
    => https_proxy=http://10.44.0.10:3128 (and HTTP_, no_proxy...)
  $ curl -sv https://ssm.us-west-2.amazonaws.com 2>&1 | grep -i connect
    => -s = no progress bar. -v = show the conversation
    => 2>&1 = -v talks on stderr: send it into the pipe too
    => Connected to 10.44.0.10 ... port 3128
    => CONNECT tunnel established, response 200
    => my shell goes via the proxy and gets through. (The SSL error
       after it is the drill's stand-in for AWS: ignore it)
  $ sudo curl -sS --max-time 5 https://ssm.us-west-2.amazonaws.com
    => -S = still show errors. --max-time 5 = give up after 5 s
    => curl: (28) Connection timed out: sudo drops my variables, so
       this is a direct connection, like the agent's. It dies.
  $ sudo journalctl -u amazon-ssm-agent | grep -i proxy
    => -u = only this unit's log lines
    => https_proxy:     <- empty. The agent never got the proxy
SAY: "My login shell reads /etc/environment. A systemd service does
      not. The agent tries AWS directly and the filter drops it."

## 3 ACT
SAY: "I'll give the service its own proxy settings in a drop-in, so a
      package update can't overwrite them, then restart it."
  $ sudo systemctl edit amazon-ssm-agent
    => edit = open an editor on a drop-in override for this unit
    => the cursor starts on line 1: arrow DOWN twice to the empty line
       under "### Anything between here...". Typed anywhere else, it
       is thrown away ("canceled: temporary file is empty"). Type:
      [Service]
      Environment="https_proxy=http://10.44.0.10:3128"
      Environment="http_proxy=http://10.44.0.10:3128"
      Environment="no_proxy=169.254.169.254,localhost,127.0.0.1"
    => no_proxy: never send the metadata address through the proxy
    => nano: Ctrl-O Enter saves, Ctrl-X quits. It saves to
       /etc/systemd/system/amazon-ssm-agent.service.d/override.conf
       and reloads systemd for you
  $ sudo systemctl restart amazon-ssm-agent
    => the environment is only read when the process starts

## 4 VERIFY
SAY: "Proving it: the agent's log, its proxy lines, and the drop-in
      that survives a reboot."
  $ sudo tail -5 /var/log/amazon/ssm/amazon-ssm-agent.log
    => HealthCheck reporting agent health.
    => Successfully opened websocket connection to: wss://ssmmessages...
  $ sudo journalctl -u amazon-ssm-agent | grep -i proxy
    => the newest lines: https_proxy: http://10.44.0.10:3128
  $ systemctl cat amazon-ssm-agent
    => cat = print the unit file AND every drop-in, with their paths
    => # /etc/systemd/system/amazon-ssm-agent.service.d/override.conf
       [Service]  Environment="https_proxy=..."
  $ check

TRAP
  - Restarting the agent: it starts again with the same empty proxy.
  - Adding the proxy to /etc/environment again, or to /etc/profile.d:
    only login shells read those. A service never does.
  - systemctl set-environment, or systemctl edit --runtime: works
    today, gone after a reboot (/run is wiped at boot).
  - Only http_proxy: https:// URLs look at https_proxy.
  - Chasing DNS because of the old "no such host" lines: 38 days old
    and a different error. Today's error is a timeout.
  - Disabling the agent "because it spams errors": no remote support.
  - Fixing fwupd-refresh: a different, harmless failure.

DO IT BETTER
  - When a shell works and a service doesn't, compare environments:
    env in your shell vs what the service logs or systemctl shows.
  - sudo also drops your variables: sudo curl tests like a service.
  - Put service settings in a drop-in (systemctl edit), never in the
    packaged unit file: an agent update overwrites that.
  - ESCALATE / TELL THE CUSTOMER: "SSM agent now uses your proxy
    10.44.0.10:3128 via a systemd drop-in; box is back Online. Tell us
    before you change the proxy address or the allowlist."
