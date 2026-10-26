import json
import math
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

PORT = int(sys.argv[1])
MIB = 1 << 20


def wave(period, depth):
    return 1 + depth * math.sin(2 * math.pi * time.time() / period)


def answers():
    now = time.time()
    next_six = 6 * 3600 - (now % 86400) + (86400 if now % 86400 > 6 * 3600 else 0)
    return [
        ('kube_deployment_status_replicas_available{namespace="automations"', [({}, 1)]),
        ('kube_deployment_status_replicas_available{namespace="llm"', [({}, 1)]),
        ("sum by (verdict) (increase(automations_renovate_verdicts_total[7d]))", [({"verdict": "safe"}, 23), ({"verdict": "check"}, 4), ({"verdict": "breaking"}, 1)]),
        ("sum by (verdict) (increase(automations_renovate_verdicts_total[30d]))", [({"verdict": "safe"}, 81), ({"verdict": "check"}, 12), ({"verdict": "breaking"}, 3)]),
        ('automations_renovate_verdicts_total{verdict="breaking"}[7d]', [({}, 1)]),
        ("sum(increase(automations_renovate_verdicts_total[7d]))", [({}, 28)]),
        ('automations_renovate_requests_total{result="failed"}[7d]', [({}, 0)]),
        ('automations_renovate_requests_total{result="failed"}[30d]', [({}, 2)]),
        ("automations_renovate_last_review_timestamp_seconds", [({}, 47 * 60)]),
        ("time() - max(kube_cronjob_status_last_successful_time", [({}, (now - 6 * 3600) % 86400)]),
        ("kube_cronjob_status_last_successful_time", [({}, now - (now - 6 * 3600) % 86400)]),
        ("kube_cronjob_status_last_schedule_time", [({}, now - (now - 6 * 3600) % 86400)]),
        ("kube_cronjob_next_schedule_time", [({}, next_six)]),
        ("kube_job_status_failed", []),
        ("max by (modelName)", [({"modelName": "NVIDIA GeForce RTX 4070 Ti"}, 44)]),
        ("DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE", [({}, 12282 * MIB)]),
        ("max(DCGM_FI_DEV_FB_USED)", [({}, 8019 * MIB)]),
        ("max(DCGM_FI_DEV_GPU_UTIL)", [({}, round(18 * wave(40, 0.8)))]),
        ("max(DCGM_FI_DEV_POWER_MGMT_LIMIT)", [({}, 285)]),
        ("max(DCGM_FI_DEV_POWER_USAGE)", [({}, round(52 * wave(40, 0.5)))]),
        ("max(DCGM_FI_DEV_GPU_TEMP)", [({}, 44)]),
        ("max(DCGM_FI_DEV_SM_CLOCK)", [({}, 2610)]),
        ("max(DCGM_FI_DEV_MEM_CLOCK)", [({}, 10501)]),
        ("avg_over_time(DCGM_FI_DEV_POWER_USAGE", [({}, 14.2)]),
        ("max_over_time(DCGM_FI_DEV_GPU_TEMP", [({}, 61)]),
        ("DCGM_FI_DEV_TOTAL_ENERGY_CONSUMPTION", [({}, 0.34)]),
        ("max(DCGM_FI_DEV_XID_ERRORS)", [({}, 0)]),
        ("llamacpp:requests_processing", [({}, 0)]),
        ("llamacpp:prompt_tokens_total", [({}, 184_300)]),
        ("llamacpp:tokens_predicted_total", [({}, 21_700)]),
        ("llamacpp:prompt_tokens_seconds", [({}, 1840.5)]),
        ("llamacpp:predicted_tokens_seconds", [({}, 57.2)]),
        ("llamacpp:n_tokens_max", [({}, 11_902)]),
    ]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        url = urlsplit(self.path)
        if url.path != "/api/v1/query":
            self.send_response(404)
            self.end_headers()
            return
        query = parse_qs(url.query).get("query", [""])[0]
        result = []
        for match, rows in answers():
            if match in query:
                result = [{"metric": labels, "value": [time.time(), str(value)]} for labels, value in rows]
                break
        body = json.dumps({"status": "success", "data": {"resultType": "vector", "result": result}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


ThreadingHTTPServer(("", PORT), Handler).serve_forever()
