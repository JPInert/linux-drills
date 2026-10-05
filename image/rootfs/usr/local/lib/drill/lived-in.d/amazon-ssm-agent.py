# drill lived-in noise: an idle, healthy AWS SSM agent (hybrid-activated, mi-...).
# Runs as `python3 < this file` with argv[0]=/usr/bin/amazon-ssm-agent (see lived-in).
import ctypes, os, signal, sys, time
ctypes.CDLL(None).prctl(15, b"amazon-ssm-agen", 0, 0, 0)
LOG = "/var/log/amazon/ssm/amazon-ssm-agent.log"
VER = "3.3.987.0"


def say(level, msg):
    line = "%s %s %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), level, msg)
    print(("<4>" if level == "WARN" else "") + line, flush=True)
    try:
        with open(LOG, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


signal.signal(signal.SIGTERM, lambda *_: (say("INFO", "[amazon-ssm-agent] Stopping Core Agent"),
                                          sys.exit(0)))
for m in ("[amazon-ssm-agent] amazon-ssm-agent - v" + VER,
          "[amazon-ssm-agent] OS: linux, Arch: amd64",
          "[amazon-ssm-agent] Starting Core Agent",
          "[amazon-ssm-agent] Registrar detected. Attempting registration",
          "[amazon-ssm-agent] Agent will take identity from OnPrem",
          "[CredentialRefresher] credentialRefresher has started",
          "[CredentialRefresher] Starting credentials refresher loop",
          "[CredentialRefresher] Next credential rotation will be in 29.98 minutes",
          "[amazon-ssm-agent] [LongRunningWorkerContainer] [WorkerProvider] Worker "
          "ssm-agent-worker is not running, starting worker process"):
    say("INFO", m)
say("WARN", "[amazon-ssm-agent] Error adding the directory '/etc/amazon/ssm/appconfig' "
            "to watcher: no such file or directory")
say("INFO", "[ssm-agent-worker] [MessageService] [MGSInteractor] Starting MGSInteractor")
while True:
    time.sleep(300)
    say("INFO", "[HealthCheck] HealthCheck reporting agent health.")
