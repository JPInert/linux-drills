# grafana-no-data: dashboards say "No data" since the monitoring update

WEAK SPOT    "Grafana loads" is not "Grafana gets data". The web page and
             the datasource are two different connections: test each.
LOCAL-FIRST  Local. Grafana and Prometheus are on this box; nothing on
             the network is involved.

THE SHORT FORMS (this is all you type)
  systemctl --failed                 anything dead? (sweep)
  sudo docker ps -a                  which containers run, which restart
  curl -s localhost:3000/api/health  Grafana itself answers?
  sudo docker logs --tail 5 grafana  what fails when a panel loads
  sudo ss -tlnp | grep 909           who listens on 909x
  curl -s localhost:9090/-/ready     Prometheus answers?
  grep -r 9091 /opt/monitoring       where the wrong port comes from
  cd /opt/monitoring/grafana/provisioning/datasources
  sudo nano prometheus.yaml          url: ... :9091 -> :9090
  cd /opt/monitoring                 the compose project folder
  sudo docker compose restart grafana     re-read provisioning

## 1 OBSERVE
SAY: "Dashboards are empty but Grafana loads. First the sweep, then I
      ask Grafana why its panels are empty."
  $ systemctl --failed
    => fwupd-refresh.service failed: "Could not resolve hostname". The
       firmware-metadata refresh has no internet here. Not related.
  $ sudo docker ps -a
    => -a = all containers, also stopped ones
    => grafana  Up 11 hours     prometheus  Up 11 hours
    => nothing is crashing or restarting
  $ curl -s localhost:3000/api/health
    => -s = silent (no progress bar)
    => "database": "ok", "version": "11.2.0": the web side is fine
  $ sudo docker logs --tail 5 grafana
    => --tail 5 = only the last 5 lines
    => msg="Prometheus query failed" error="Post
       \"http://localhost:9091/api/v1/query_range\": dial tcp
       127.0.0.1:9091: connect: connection refused"
    => refused = the box answered "nobody listens on 9091"

## 2 NARROW
SAY: "Grafana asks for port 9091. Is Prometheus there?"
  $ sudo ss -tlnp | grep 909
    => -t TCP  -l listening  -n numbers  -p program (needs sudo)
    => 0.0.0.0:9090 ... users:(("prometheus",...))
    => Prometheus is on 9090. Nothing is on 9091
  $ curl -s localhost:9090/-/ready
    => Prometheus Server is Ready.
  $ curl -s "localhost:9090/api/v1/query?query=up"
    => "job": "node" ... "1": it IS collecting this box's metrics.
       The collector is fine; Grafana just asks the wrong port
  $ grep -r 9091 /opt/monitoring
    => -r = search every file below that folder
    => CHANGELOG.md: "datasource now goes through prom-auth ... on
       :9091. prom-auth is deployed only on sites with the "prom-auth"
       profile"
    => grafana/provisioning/datasources/prometheus.yaml:
       url: http://localhost:9091
  $ cat /var/log/edge-update.log
    => "profile northgate: prom-auth not enabled, skipping prom-auth"
SAY: "The update pointed Grafana at prom-auth on 9091, then skipped
      installing prom-auth here. Grafana must talk to 9090 directly."

## 3 ACT
SAY: "I fix the datasource file, not Prometheus: the NOC pulls from
      9090, so 9090 stays."
  $ cd /opt/monitoring/grafana/provisioning/datasources
  $ sudo nano prometheus.yaml
    => change   url: http://localhost:9091
       to       url: http://localhost:9090
    => Ctrl-O Enter saves, Ctrl-X quits
  $ cd /opt/monitoring
  $ sudo docker compose restart grafana
    => Grafana reads provisioning files only when it starts
    => (compose also restarts prometheus, which grafana depends on)

## 4 VERIFY
SAY: "Proving it from Grafana's side: its logs and its own datasource
      test."
  $ sudo docker logs --tail 5 grafana
    => "inserting datasource from configuration" and no new
       "Prometheus query failed" lines
  $ curl -s -u admin:Northgate-NOC \
      localhost:3000/api/datasources/uid/prometheus-edge/health
    => -u = user:password (it is in compose.yaml,
       GF_SECURITY_ADMIN_PASSWORD)
    => "Successfully queried the Prometheus API.", "status": "OK"
  $ check

TRAP
  - Restarting Grafana without the edit: same file, same 9091.
  - Editing the file but not restarting: Grafana read it at start.
  - Moving Prometheus to 9091 "to match": the NOC's central server
    pulls from 9090 and goes blind.
  - Deleting the datasource: the errors stop, and so does the data.
  - A hand-run forwarder 9091 -> 9090: gone after a reboot.
  - Chasing fwupd-refresh or "the firewall": nothing here crosses the
    network.

DO IT BETTER
  - Test both ends of the failing hop: who asks (Grafana's log) and
    who should answer (ss -tlnp, curl the port).
  - grep -r the bad value to find which file set it, and the
    changelog to learn why.
  - ESCALATE / TELL THE VENDOR: "monitoring 2.0 wrote prom-auth :9091
    into Grafana's datasource on a site without prom-auth. Set it back
    to :9090 here; please fix the template for non-prom-auth sites."
