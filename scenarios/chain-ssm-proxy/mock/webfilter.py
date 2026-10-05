#!/usr/bin/python3
# drill: stands in for the CUSTOMER's web-filter proxy (10.44.0.10:3128).
# It is not part of edge-nvr-03; it only lives in this box because the drill
# has no second machine. Allowlist: *.amazonaws.com (the IT ticket asked for
# the AWS SSM endpoints). CONNECT to an allowed host answers 200 and then
# stands in for AWS (no real upstream); anything else is blocked with 403.
import socket, sys, threading, time

ADDR = ("10.44.0.10", 3128)
ALLOW = (".amazonaws.com",)
BLOCK = (b"HTTP/1.1 403 Forbidden\r\nContent-Type: text/html\r\nConnection: close\r\n"
         b"Content-Length: 61\r\n\r\n<html><body>Blocked by Northgate Garage web filter</body></html>\n")


def log(msg):
    print(msg, flush=True)


def handle(c, peer):
    try:
        c.settimeout(10)
        data = b""
        while b"\r\n\r\n" not in data and len(data) < 8192:
            chunk = c.recv(4096)
            if not chunk:
                return
            data += chunk
        line = data.split(b"\r\n", 1)[0].decode("latin-1", "replace")
        parts = line.split()
        if len(parts) < 2:
            c.sendall(b"HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n")
            return
        meth, target = parts[0], parts[1]
        host = target.split("://", 1)[-1].split("/", 1)[0].rsplit(":", 1)[0].lower()
        ok = any(host.endswith(a) for a in ALLOW)
        log("%s %s %s %s" % (peer[0], meth, target, "ALLOW" if ok else "DENY"))
        if not ok:
            c.sendall(BLOCK)
            return
        if meth == "CONNECT":
            c.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")
            # stand-in for AWS: hold the tunnel briefly, then close
            try:
                c.settimeout(2)
                c.recv(4096)
            except OSError:
                pass
            return
        body = b"<html><body>AWS endpoint (drill stand-in)</body></html>\n"
        c.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n"
                  b"Content-Length: %d\r\n\r\n" % len(body) + body)
    except OSError:
        pass
    finally:
        c.close()


def main():
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    for _ in range(50):
        try:
            s.bind(ADDR)
            break
        except OSError:
            time.sleep(0.2)
    else:
        sys.exit("cannot bind %s:%d" % ADDR)
    s.listen(64)
    log("web filter proxy (drill stand-in) listening on %s:%d" % ADDR)
    while True:
        c, peer = s.accept()
        threading.Thread(target=handle, args=(c, peer), daemon=True).start()


main()
