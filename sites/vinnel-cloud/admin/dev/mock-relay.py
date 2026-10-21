import json
import math
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FORWARDS = json.load(open(sys.argv[1]))
BOOT = time.time() - 3 * 86400 - 4 * 3600
MIB = 1 << 20
RATES = {
    "http": (0.15, 2_000),
    "https": (0.8, 60_000),
    "minecraft": (0.002, 3_000_000),
    "satisfactory-tcp": (0.001, 5_000_000),
    "satisfactory-udp": (0.0005, 8_000_000),
    "satisfactory-messaging": (0.0003, 40_000),
    "gitlab-ssh": (0.0008, 200_000),
}
DROPS = {"input": 2.0, "forward": 0.05, "output": 0.0}


def wave(t, period, depth):
    return 1 + depth * math.sin(2 * math.pi * t / period)


def counter(rate, t, period=600, depth=0.4):
    return int(rate * t + rate * depth * period / (2 * math.pi) * (1 - math.cos(2 * math.pi * t / period)))


def metrics():
    now = time.time()
    up = now - BOOT
    lines = [
        f"node_time_seconds {now:.3f}",
        f"node_boot_time_seconds {BOOT:.0f}",
        f'node_cpu_seconds_total{{cpu="0",mode="idle"}} {up * 0.96:.2f}',
        f'node_cpu_seconds_total{{cpu="0",mode="user"}} {up * 0.025:.2f}',
        f'node_cpu_seconds_total{{cpu="0",mode="system"}} {up * 0.015:.2f}',
        f"node_memory_MemTotal_bytes {976 * MIB}",
        f"node_memory_MemAvailable_bytes {int(704 * MIB * wave(now, 900, 0.03))}",
        f"node_nf_conntrack_entries {int(310 * wave(now, 300, 0.25))}",
        "node_nf_conntrack_entries_limit 65536",
    ]
    for device, rx, tx in (("eth0", 190_000, 220_000), ("wg0", 170_000, 200_000), ("lo", 300, 300)):
        lines.append(f'node_network_receive_bytes_total{{device="{device}"}} {counter(rx, up)}')
        lines.append(f'node_network_transmit_bytes_total{{device="{device}"}} {counter(tx, up)}')
    lines += [
        f"relay_wireguard_latest_handshake_seconds {int(now - now % 120)}",
        f"relay_wireguard_receive_bytes_total {counter(170_000, up)}",
        f"relay_wireguard_transmit_bytes_total {counter(200_000, up)}",
    ]
    for name, forward in FORWARDS.items():
        rate, size = RATES.get(name, (0.001, 100_000))
        labels = f'forward="{name}",protocol="{forward["protocol"]}",port="{forward["port"]}"'
        lines.append(f"relay_forward_connections_total{{{labels}}} {counter(rate, up)}")
        lines.append(f"relay_forward_bytes_total{{{labels}}} {counter(rate * size, up)}")
    for chain, rate in DROPS.items():
        lines.append(f'relay_firewall_dropped_packets_total{{chain="{chain}"}} {counter(rate, up)}')
    return ("\n".join(lines) + "\n").encode()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_error(404)
            return
        body = metrics()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


ThreadingHTTPServer(("0.0.0.0", int(sys.argv[2])), Handler).serve_forever()
