import json
import math
import ssl
import sys
import time
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

NODE = "hestia"
TOKEN = "Bearer local-dev-token"
STARTED = time.time()
MIB = 1 << 20

WORKLOADS = {
    "forge": [("gitlab-0", 450, 3600), ("gitlab-runner", 20, 90), ("gitlab-runner-privileged", 15, 80)],
    "observability": [("vmsingle-vm", 120, 900), ("vmagent-vm", 40, 220), ("grafana", 30, 260), ("loki-0", 80, 700), ("tempo-0", 40, 380), ("otel-collector", 50, 200)],
    "files": [("nextcloud", 90, 700), ("nextcloud-cron", 5, 60)],
    "storage": [("seaweedfs-master-0", 40, 180), ("seaweedfs-volume-0", 70, 600), ("seaweedfs-filer-0", 50, 300)],
    "auth": [("authelia", 10, 60)],
    "matrix": [("synapse", 60, 420), ("synapse-postgres", 25, 180)],
    "miniflux": [("miniflux", 5, 40), ("miniflux-postgres", 10, 90)],
    "proxy": [("netbird-management", 15, 80), ("netbird-signal", 5, 30), ("netbird-relay", 10, 40), ("netbird-dashboard", 2, 20)],
    "dns": [("adguard-0", 20, 90)],
    "registry": [("registry-cache", 10, 60)],
    "searxng": [("searxng", 15, 180)],
    "vin-moe": [("vin-moe-site-1", 2, 12), ("vin-moe-site-2", 2, 12)],
    "vinnel-cloud": [("vinnel-cloud-site", 3, 20), ("vinnel-cloud-admin", 8, 40), ("vinnel-cloud-auth", 1, 10), ("shell", 2, 20)],
    "platform": [("ingress-nginx-controller", 30, 160), ("metrics-server", 6, 30), ("vpa-recommender", 4, 30)],
    "kube-system": [("cilium", 120, 400), ("cilium-operator", 8, 60), ("coredns-1", 6, 30), ("coredns-2", 6, 30), ("hubble-relay", 3, 30)],
    "cert-manager": [("cert-manager", 4, 40), ("cert-manager-cainjector", 3, 40), ("cert-manager-webhook", 2, 20)],
}

VOLUMES = [
    ("forge", "gitlab-data", 50), ("forge", "gitlab-config", 1), ("observability", "vmsingle-vm", 30),
    ("files", "nextcloud-data", 10),
    ("matrix", "synapse-media", 10), ("vinnel-cloud", "vinnel-cloud-admin-blog-pvc", 1),
    ("vinnel-cloud", "vinnel-cloud-admin-blog-media-pvc", 5), ("dns", "adguard-work", 1),
]


def wave(name, period=180, spread=0.3):
    phase = (zlib.crc32(name.encode()) % 628) / 100
    return 1 + spread * math.sin(2 * math.pi * time.time() / period + phase)


def crashlooping():
    return int((time.time() - STARTED) // 120) % 2 == 1


def pods():
    items = []
    for ns, workloads in WORKLOADS.items():
        for name, _, _ in workloads:
            status = {"phase": "Running", "containerStatuses": [{"restartCount": 0, "state": {"running": {}}}]}
            if name == "searxng" and crashlooping():
                status["containerStatuses"] = [{"restartCount": 7, "state": {"waiting": {"reason": "CrashLoopBackOff"}}}]
            items.append({"metadata": {"name": name, "namespace": ns}, "spec": {"nodeName": NODE}, "status": status})
    items.append({"metadata": {"name": "vinnel-cloud-admin-blog-sync-29340720", "namespace": "vinnel-cloud"}, "spec": {"nodeName": NODE},
                  "status": {"phase": "Succeeded", "containerStatuses": []}})
    return items


def pod_metrics():
    items = []
    for ns, workloads in WORKLOADS.items():
        for name, cpu, mem in workloads:
            if name == "searxng" and crashlooping():
                continue
            usage = {"cpu": f"{int(cpu * wave(name)) * 1000000}n", "memory": f"{int(mem * MIB * wave(name, 600, 0.08)) // 1024}Ki"}
            items.append({"metadata": {"name": name, "namespace": ns}, "containers": [{"name": name, "usage": usage}]})
    return items


def node_metrics():
    cpu = 600.0
    mem = 2048.0 * MIB
    for item in pod_metrics():
        for c in item["containers"]:
            cpu += int(c["usage"]["cpu"][:-1]) / 1e6
            mem += int(c["usage"]["memory"][:-2]) * 1024
    return [{"metadata": {"name": NODE}, "usage": {"cpu": f"{int(cpu)}m", "memory": f"{int(mem) // 1024}Ki"}}]


def nodes():
    return [{
        "metadata": {"name": NODE},
        "status": {
            "allocatable": {"cpu": "8", "memory": "32Gi", "pods": "110"},
            "conditions": [{"type": "Ready", "status": "True"}],
            "nodeInfo": {"kubeletVersion": "v1.37.1"},
        },
    }]


def volumes():
    return [{
        "metadata": {"name": f"pvc-{zlib.crc32(claim.encode()):08x}"},
        "spec": {"capacity": {"storage": f"{size}Gi"}, "storageClassName": "local-path",
                 "claimRef": {"namespace": ns, "name": claim}},
        "status": {"phase": "Bound"},
    } for ns, claim, size in VOLUMES]


def claims():
    return [{"metadata": {"name": claim, "namespace": ns}, "spec": {"storageClassName": "local-path"}}
            for ns, claim, _ in VOLUMES]


ROUTES = {
    "/api/v1/nodes": nodes,
    "/api/v1/pods": pods,
    "/api/v1/persistentvolumes": volumes,
    "/api/v1/persistentvolumeclaims": claims,
    "/apis/metrics.k8s.io/v1beta1/nodes": node_metrics,
    "/apis/metrics.k8s.io/v1beta1/pods": pod_metrics,
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get("Authorization") != TOKEN:
            return self.reply(401, {"kind": "Status", "code": 401})
        path = urlparse(self.path).path
        if path in ROUTES:
            return self.reply(200, {"items": ROUTES[path]()})
        parts = path.strip("/").split("/")
        if len(parts) == 5 and parts[:3] == ["api", "v1", "namespaces"] and parts[4] == "pods":
            return self.reply(200, {"items": [p for p in pods() if p["metadata"]["namespace"] == parts[3]]})
        return self.reply(404, {"kind": "Status", "code": 404, "message": f"{path} is not mocked"})

    def reply(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        pass


server = ThreadingHTTPServer(("127.0.0.1", int(sys.argv[3])), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(sys.argv[1], sys.argv[2])
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
