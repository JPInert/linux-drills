#!/usr/bin/python3
"""LAB STAND-IN for DHCP clients on the camera WiFi segment (raw frames on an interface, like dhclient).
  dhcpsim.py cams IFACE          the two new WiFi cameras: DISCOVER until they get a lease, then renew
  dhcpsim.py probe IFACE [MAC]   one DISCOVER; print the OFFER's address, server, router, DNS, or 'none'
  dhcpsim.py sniff IFACE SECS MAC...   watch the server's replies going out IFACE (the box's eth1); print
                                       "MAC TYPE ADDRESS ROUTER DNS" per reply, stop once every MAC got an ACK
The cameras run in the lab's own container (lab-side.sh); `sniff` is what check.sh runs on the box.
"""
import os, random, socket, struct, sys, time


def csum(b):
    if len(b) % 2: b += b"\0"
    s = sum(struct.unpack("!%dH" % (len(b) // 2), b))
    while s >> 16: s = (s & 0xffff) + (s >> 16)
    return ~s & 0xffff


def frame(mac, xid, mtype, extra=b"", host=None):
    opts = b"\x63\x82\x53\x63" + bytes([53, 1, mtype]) + extra
    if host:
        opts += bytes([12, len(host)]) + host.encode()
    opts += bytes([55, 3, 1, 3, 6, 255])
    bootp = struct.pack("!BBBBIHH4s4s4s4s16s64s128s", 1, 1, 6, 0, xid, 0, 0x8000, b"\0" * 4, b"\0" * 4,
                        b"\0" * 4, b"\0" * 4, mac + b"\0" * 10, b"\0" * 64, b"\0" * 128) + opts
    udp = struct.pack("!HHHH", 68, 67, 8 + len(bootp), 0) + bootp
    ip = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(udp), random.randrange(65536), 0, 64, 17, 0,
                     b"\0" * 4, b"\xff" * 4)
    ip = ip[:10] + struct.pack("!H", csum(ip)) + ip[12:]
    return b"\xff" * 6 + mac + b"\x08\x00" + ip + udp


def parse(pkt, xid):
    if len(pkt) < 282 or pkt[12:14] != b"\x08\x00" or pkt[23] != 17: return None
    ihl = (pkt[14] & 15) * 4
    u = 14 + ihl
    if struct.unpack("!H", pkt[u + 2:u + 4])[0] != 68: return None
    b = pkt[u + 8:]
    if b[0] != 2 or struct.unpack("!I", b[4:8])[0] != xid: return None
    yiaddr = socket.inet_ntoa(b[16:20])
    o, i, opts = b[240:], 0, {}
    while i < len(o) and o[i] != 255:
        if o[i] == 0: i += 1; continue
        opts[o[i]] = o[i + 2:i + 2 + o[i + 1]]; i += 2 + o[i + 1]
    ip4 = lambda k: socket.inet_ntoa(opts[k][:4]) if len(opts.get(k, b"")) >= 4 else "none"
    return {"type": opts.get(53, b"\0")[0], "yiaddr": yiaddr, "router": ip4(3), "dns": ip4(6),
            "server": socket.inet_ntoa(opts[54]) if 54 in opts else "?"}


def exchange(s, mac, xid, mtype, extra=b"", host=None, want=2, wait=2.0):
    s.send(frame(mac, xid, mtype, extra, host))
    end = time.time() + wait
    while time.time() < end:
        s.settimeout(max(0.05, end - time.time()))
        try:
            r = parse(s.recv(2048), xid)
        except socket.timeout:
            break
        if r and r["type"] in (want, 6):
            return r
    return None


def sock(iface):
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0800))
    s.bind((iface, 0))
    return s


def lease(s, mac, host):
    xid = random.randrange(1 << 32)
    off = exchange(s, mac, xid, 1, host=host, wait=4.0)   # dnsmasq pings a new address ~3 s first
    if not off or off["type"] != 2:
        return None
    req = bytes([50, 4]) + socket.inet_aton(off["yiaddr"]) + bytes([54, 4]) + socket.inet_aton(off["server"])
    ack = exchange(s, mac, xid, 3, req, host, want=5)
    return ack["yiaddr"] if ack and ack["type"] == 5 else None


def main():
    what, iface = sys.argv[1], sys.argv[2]
    s = sock(iface)
    if what == "sniff":
        s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0003))
        s.bind((iface, 0))
        end, want, acked = time.time() + float(sys.argv[3]), set(m.lower() for m in sys.argv[4:]), set()
        while time.time() < end and not (want and want <= acked):
            s.settimeout(max(0.05, end - time.time()))
            try:
                pkt = s.recv(2048)
            except socket.timeout:
                break
            if len(pkt) < 282 or pkt[12:14] != b"\x08\x00" or pkt[23] != 17:
                continue
            u = 14 + (pkt[14] & 15) * 4
            if struct.unpack("!H", pkt[u + 2:u + 4])[0] != 68 or pkt[u + 8] != 2:
                continue
            r = parse(pkt, struct.unpack("!I", pkt[u + 12:u + 16])[0])
            mac = ":".join("%02x" % c for c in pkt[u + 8 + 28:u + 8 + 34])
            if r:
                print(mac, r["type"], r["yiaddr"], r["router"], r["dns"], flush=True)
                if r["type"] == 5: acked.add(mac)
        return
    if what == "probe":
        mac = bytes.fromhex((sys.argv[3] if len(sys.argv) > 3 else "02:00:5e:10:99:01").replace(":", ""))
        r = exchange(s, mac, random.randrange(1 << 32), 1, wait=5.0)   # dnsmasq pings a new address first
        print("%s %s %s %s" % (r["yiaddr"], r["server"], r["router"], r["dns"]) if r and r["type"] == 2 else "none")
        return
    cams = [(bytes.fromhex("3cef8c1a2b01"), "wificam-rm207"), (bytes.fromhex("3cef8c1a2b02"), "wificam-rm212")]
    import threading

    def cam(mac, host):
        s = sock(iface)
        while True:
            ip = lease(s, mac, host)
            time.sleep(4 if ip else 0.5)          # renew every few seconds (check.sh watches); retry fast while refused
    for mac, host in cams:
        threading.Thread(target=cam, args=(mac, host), daemon=True).start()
    while True:
        time.sleep(3600)


main()
