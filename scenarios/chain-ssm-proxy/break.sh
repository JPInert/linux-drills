# chain-ssm-proxy: the customer's new web filter drops direct HTTPS; egress
# must go through their proxy. IT set the proxy in /etc/environment (login
# shells), but systemd services never read that file, so amazon-ssm-agent
# still dials AWS directly and times out. The fix is a unit drop-in.
/usr/local/lib/drill/lived-in --no-ssm >/dev/null 2>&1

# --- the site network, simulated: direct web traffic (tcp 80/443) goes into a
# dummy link and never returns (= the customer's firewall dropping it); the
# customer's proxy is a stand-in listening on 10.44.0.10:3128.
ip link add drillsim0 type dummy
ip addr add 10.44.0.10/32 dev drillsim0
ip link set drillsim0 up
ip route add default dev drillsim0 table 100
ip rule add ipproto tcp dport 443 table 100 pref 100
ip rule add ipproto tcp dport 80 table 100 pref 101

install -d -m 0755 /usr/local/lib/drill-sim
install -m 0755 /drill/mock/webfilter.py /usr/local/lib/drill-sim/webfilter.py
cat > /usr/lib/systemd/system/drill-sim-webfilter.service <<'UNIT'
[Unit]
Description=DRILL SIMULATION: the customer's web-filter proxy (not part of this box)

[Service]
ExecStart=/usr/bin/python3 /usr/local/lib/drill-sim/webfilter.py
Restart=always
RestartSec=1
UNIT

# --- what Northgate Garage IT pushed when the filter went live
cat >> /etc/environment <<'ENV'
# Northgate Garage IT - web filter go-live: all outbound web via the proxy
http_proxy=http://10.44.0.10:3128
https_proxy=http://10.44.0.10:3128
HTTP_PROXY=http://10.44.0.10:3128
HTTPS_PROXY=http://10.44.0.10:3128
no_proxy=localhost,127.0.0.1,169.254.169.254,10.50.0.0/16,.northgate.lan
NO_PROXY=localhost,127.0.0.1,169.254.169.254,10.50.0.0/16,.northgate.lan
ENV
cat > /etc/profile.d/northgate-proxy.sh <<'SH'
# Northgate Garage IT: load the site proxy settings into interactive shells
set -a
. /etc/environment
set +a
SH
chmod 0644 /etc/environment /etc/profile.d/northgate-proxy.sh

# --- the SSM agent, installed the way the .deb installs it
install -m 0755 /drill/mock/amazon-ssm-agent.py /usr/bin/amazon-ssm-agent
cat > /usr/lib/systemd/system/amazon-ssm-agent.service <<'UNIT'
[Unit]
Description=amazon-ssm-agent
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/usr/bin/
ExecStart=/usr/bin/amazon-ssm-agent
KillMode=process
Restart=on-failure
RestartForceExitStatus=SIGPIPE
RestartSec=15min

[Install]
WantedBy=multi-user.target
UNIT
install -d -m 0755 /etc/amazon/ssm /var/log/amazon/ssm
install -d -m 0700 /var/lib/amazon/ssm
printf '{"ManagedInstanceID":"mi-0c4e1b7a9d2f35e61","Region":"us-west-2"}\n' \
  > /var/lib/amazon/ssm/registration
chmod 0600 /var/lib/amazon/ssm/registration
cat > /etc/amazon/ssm/seelog.xml <<'XML'
<seelog type="adaptive" mininterval="2000000" maxinterval="100000000" critmsgcount="500" minlevel="info">
    <outputs formatid="fmtinfo">
        <console formatid="fmtinfo"/>
        <rollingfile type="size" filename="/var/log/amazon/ssm/amazon-ssm-agent.log" maxsize="30000000" maxrolls="5"/>
        <filter levels="error,critical" formatid="fmterror">
            <rollingfile type="size" filename="/var/log/amazon/ssm/errors.log" maxsize="10000000" maxrolls="5"/>
        </filter>
    </outputs>
</seelog>
XML

# --- history: healthy for days, one old DNS blip (an ISP outage, long fixed),
# then nothing but timeouts since the filter went live yesterday at 16:00
python3 - <<'PY'
import time, datetime as dt
L = "/var/log/amazon/ssm/amazon-ssm-agent.log"
E = "/var/log/amazon/ssm/errors.log"
now = time.time()
cut = dt.datetime.combine(dt.date.today() - dt.timedelta(days=1), dt.time(16, 0, 7)).timestamp()
W = "[ssm-agent-worker]"
log, err = [], []
def ts(t): return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t))
def add(t, lvl, comp, msg):
    ln = "%s %s %s %s" % (ts(t), lvl, comp, msg)
    log.append(ln)
    if lvl == "ERROR": err.append(ln)
old = now - 38 * 86400 + 3 * 3600
for i in range(4):
    t = old + i * 300
    add(t, "ERROR", W + " [HealthCheck]", "error when calling AWS APIs. error details - "
        "RequestError: send request failed")
    add(t, "ERROR", W + " [HealthCheck]", 'caused by: Post "https://ssm.us-west-2.'
        'amazonaws.com/": dial tcp: lookup ssm.us-west-2.amazonaws.com: no such host')
add(old + 1500, "INFO", W + " [HealthCheck]", "HealthCheck reporting agent health.")
start = now - 9 * 86400
add(start, "INFO", "[amazon-ssm-agent]", "amazon-ssm-agent - v3.3.987.0")
add(start, "INFO", "[amazon-ssm-agent]", "Starting Core Agent")
add(start + 2, "INFO", W + " [MessageService] [MGSInteractor]", "Successfully opened "
    "websocket connection to: wss://ssmmessages.us-west-2.amazonaws.com/v1/control-channel/"
    "mi-0c4e1b7a9d2f35e61?role=subscribe&stream=input")
t = start + 300
while t < cut:
    add(t, "INFO", W + " [HealthCheck]", "HealthCheck reporting agent health.")
    t += 1800
t = cut
while t < now - 60:
    add(t, "ERROR", W + " [HealthCheck]", "error when calling AWS APIs. error details - "
        "RequestError: send request failed")
    add(t, "ERROR", W + " [HealthCheck]", 'caused by: Post "https://ssm.us-west-2.'
        'amazonaws.com/": dial tcp 52.94.225.18:443: i/o timeout')
    add(t + 3, "ERROR", W + " [MessageService] [MessageHandler] [EC2MessagesClient]",
        "error when calling AWS APIs. error details - RequestError: send request failed")
    add(t + 3, "ERROR", W + " [MessageService] [MessageHandler] [EC2MessagesClient]",
        'caused by: Post "https://ec2messages.us-west-2.amazonaws.com/": dial tcp '
        '52.94.228.170:443: i/o timeout')
    t += 900
open(L, "w").write("\n".join(log) + "\n")
open(E, "w").write("\n".join(err) + "\n")
PY
chmod 0644 /var/log/amazon/ssm/amazon-ssm-agent.log /var/log/amazon/ssm/errors.log

# --- the site notes the NOC keeps on every box
cat > /home/tech/SITE-NOTES.txt <<NOTES
Northgate Garage (level 2) - edge-nvr-03 - site notes
------------------------------------------------------
Site IT contact: Dana Ruiz (Northgate Garage IT)   Cameras: 10.50.1.21-.26
Remote access: AWS SSM (hybrid activation), out-of-band console as backup

$(date -d '38 days ago' +%F)  ISP DNS outage ~2 h, box showed Connection Lost,
            came back by itself when the ISP fixed DNS. No action.
$(date -d '9 days ago' +%F)  Agent updated to 3.3.987.0 (routine).
$(date -d 'yesterday' +%F)  Northgate Garage IT turned on their new web filter
            at 16:00. From now on ALL outbound web traffic must go
            through their proxy: http://10.44.0.10:3128 (they
            allowlisted *.amazonaws.com for us). Dana set the proxy
            in /etc/environment on the box. Direct HTTPS is dropped.
NOTES
chown tech:tech /home/tech/SITE-NOTES.txt

systemctl daemon-reload
systemctl enable --now drill-sim-webfilter.service >/dev/null 2>&1
systemctl enable amazon-ssm-agent.service >/dev/null 2>&1
for _ in $(seq 1 40); do (exec 3<>/dev/tcp/10.44.0.10/3128) 2>/dev/null && break; sleep 0.25; done
(exec 3<>/dev/tcp/10.44.0.10/3128) 2>/dev/null
rm -f /run/.drill-ssm-state
systemctl restart amazon-ssm-agent.service
for _ in $(seq 1 40); do [ -f /run/.drill-ssm-state ] && break; sleep 0.25; done
systemctl is-active --quiet amazon-ssm-agent
