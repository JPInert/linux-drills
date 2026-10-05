#!/usr/bin/python3
# drill mock of amazon-ssm-agent 3.3 on a hybrid (on-prem, mi-) instance.
# Logs like the real agent to stdout (journal) and
# /var/log/amazon/ssm/amazon-ssm-agent.log. It is "online" only when a
# CONNECT through the https_proxy in ITS OWN environment succeeds: the
# site's web filter drops every direct HTTPS connection (that part is
# simulated: direct dials always time out, as they would at this site).
import json, os, signal, socket, sys, time

VERSION = "3.3.987.0"
REGION = "us-west-2"
MI = "mi-0c4e1b7a9d2f35e61"
LOGF = "/var/log/amazon/ssm/amazon-ssm-agent.log"
ERRF = "/var/log/amazon/ssm/errors.log"
STATE = "/run/.drill-ssm-state"            # read by check.sh only
EP = {"ssm": "52.94.225.18", "ec2messages": "52.94.228.170",
      "ssmmessages": "52.119.169.54"}


def log(level, comp, msg):
    line = "%s %s %s %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), level, comp, msg)
    print({"ERROR": "<3>", "WARN": "<4>"}.get(level, "") + line, flush=True)
    for fn in (LOGF, ERRF) if level == "ERROR" else (LOGF,):
        try:
            with open(fn, "a") as f:
                f.write(line + "\n")
        except OSError:
            pass


def env(name):
    return os.environ.get(name.lower()) or os.environ.get(name.upper()) or ""


def state(online):
    try:
        with open(STATE + ".tmp", "w") as f:
            f.write("%d %d %d\n" % (os.getpid(), 1 if online else 0, int(time.time())))
        os.chmod(STATE + ".tmp", 0o600)
        os.replace(STATE + ".tmp", STATE)
    except OSError:
        pass


def parse_proxy(p):
    p = p.strip()
    if "://" in p:
        scheme, p = p.split("://", 1)
        if scheme not in ("http", "https"):
            return None, None, 'proxyconnect tcp: unsupported proxy scheme "%s"' % scheme
    p = p.split("/", 1)[0].split("@")[-1]
    host, _, port = p.rpartition(":")
    if not host:
        host, port = port, "80"
    try:
        return host, int(port), None
    except ValueError:
        return None, None, 'parse "%s": invalid port' % p


def dial(svc):
    """-> None on success, else the Go-style error text"""
    host = "%s.%s.amazonaws.com" % (svc, REGION)
    px = env("https_proxy")
    if not px:
        time.sleep(3)          # the web filter drops the SYN: a timeout, not a refusal
        return "dial tcp %s:443: i/o timeout" % EP[svc]
    h, port, err = parse_proxy(px)
    if err:
        return err
    try:
        s = socket.create_connection((h, port), timeout=3)
    except socket.timeout:
        return "proxyconnect tcp: dial tcp %s:%d: i/o timeout" % (h, port)
    except socket.gaierror:
        return "proxyconnect tcp: dial tcp: lookup %s: no such host" % h
    except OSError as e:
        why = "connection refused" if getattr(e, "errno", 0) == 111 else \
            (e.strerror or str(e)).lower()
        return "proxyconnect tcp: dial tcp %s:%d: connect: %s" % (h, port, why)
    try:
        s.settimeout(3)
        s.sendall(("CONNECT %s:443 HTTP/1.1\r\nHost: %s:443\r\nUser-Agent: "
                   "amazon-ssm-agent/%s\r\n\r\n" % (host, host, VERSION)).encode())
        resp = s.recv(1024).decode("latin-1", "replace")
    except OSError:
        return "proxyconnect tcp: read tcp: i/o timeout"
    finally:
        s.close()
    first = resp.split("\r\n", 1)[0]
    parts = first.split(" ", 2)
    if len(parts) >= 2 and parts[1] == "200":
        return None
    return parts[2] if len(parts) > 2 else "malformed HTTP response %r" % first


def fail(comp, verb, svc, err):
    log("ERROR", comp, "error when calling AWS APIs. error details - RequestError: "
        "send request failed")
    log("ERROR", comp, 'caused by: %s "https://%s.%s.amazonaws.com/": %s'
        % (verb, svc, REGION, err))


def main():
    signal.signal(signal.SIGTERM, lambda *_: (
        log("INFO", "[amazon-ssm-agent]", "Stopping Core Agent"),
        log("INFO", "[amazon-ssm-agent]", "Bye."), state(False), sys.exit(0)))
    if len(sys.argv) > 1 and sys.argv[1] in ("-version", "--version", "version"):
        print("SSM Agent version: " + VERSION)
        return
    os.makedirs(os.path.dirname(LOGF), exist_ok=True)
    state(False)
    A = "[amazon-ssm-agent]"
    log("INFO", "[amazon-ssm-agent]", "amazon-ssm-agent - v" + VERSION)
    log("INFO", A, "OS: linux, Arch: amd64")
    log("INFO", A, "Proxy environment variables:")
    for k in ("http_proxy", "https_proxy", "no_proxy"):
        log("INFO", A, "%s: %s" % (k, env(k)))
    log("INFO", A, "Checking if agent identity type OnPrem can be assumed")
    log("INFO", A, "Agent will take identity from OnPrem")
    np = env("no_proxy")
    if env("http_proxy") and "169.254.169.254" not in np:
        log("WARN", "[EC2Identity]", "metadata request to 169.254.169.254 went through "
            "the proxy and was refused (403 Forbidden): add 169.254.169.254 to no_proxy")
    log("INFO", A, "registrar detected. Attempting registration")
    log("INFO", A, "Registration attempted. Resuming core agent startup.")
    log("INFO", "[CredentialRefresher]", "credentialRefresher has started")
    log("INFO", "[CredentialRefresher]", "Starting credentials refresher loop")
    log("INFO", A, "Starting Core Agent")
    log("INFO", A, "[LongRunningWorkerContainer] [WorkerProvider] Worker ssm-agent-worker "
        "is not running, starting worker process")
    W = "[ssm-agent-worker]"
    online = None
    while True:
        err = dial("ssm")
        if err is None:
            if online is not True:
                log("INFO", "[CredentialRefresher]", "Credentials ready")
                log("INFO", W + " [HealthCheck]", "HealthCheck reporting agent health.")
                log("INFO", W + " [MessageService] [MessageHandler]",
                    "ec2messages: GetMessages polling started for " + MI)
                log("INFO", W + " [MessageService] [MGSInteractor]",
                    "Successfully opened websocket connection to: wss://ssmmessages."
                    "%s.amazonaws.com/v1/control-channel/%s?role=subscribe&stream=input"
                    % (REGION, MI))
            else:
                log("INFO", W + " [HealthCheck]", "HealthCheck reporting agent health.")
            online = True
            state(True)
            time.sleep(10)
            continue
        fail(W + " [HealthCheck]", "Post", "ssm", err)
        state(False)
        if online is not False or int(time.time()) % 3 == 0:
            e2 = dial("ec2messages")
            if e2:
                fail(W + " [MessageService] [MessageHandler] [EC2MessagesClient]",
                     "Post", "ec2messages", e2)
            e3 = dial("ssmmessages")
            if e3:
                log("ERROR", W + " [MessageService] [MGSInteractor]",
                    "failed to connect to control channel: dial tcp to wss://ssmmessages."
                    "%s.amazonaws.com: %s" % (REGION, e3))
                log("INFO", W + " [MessageService] [MGSInteractor]",
                    "Retrying connection to ssmmessages in 30 seconds")
        online = False
        time.sleep(4)


main()
