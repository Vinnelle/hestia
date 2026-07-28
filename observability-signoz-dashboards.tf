resource "restapi_object" "dashboard" {
  for_each = fileset(path.module, "signoz-dashboards/**/*.json")

  path = "/api/v1/dashboards"
  data = file("${path.module}/${each.value}")

  lifecycle {
    ignore_changes = [data]
  }
}

import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-system-monitoring/kubernetes-coredns.json"]
  id = "/api/v1/dashboards/019fa952-84e5-7a3b-a52a-230c228d9229"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-infra-metrics/kubernetes-node-metrics-overall.json"]
  id = "/api/v1/dashboards/019fa952-879b-78da-be0f-b0288e79fe56"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-system-monitoring/kubernetes-kube-proxy.json"]
  id = "/api/v1/dashboards/019fa952-8b82-705e-83d3-314874c02cbc"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/opentelemetry-collector/opentelemetry-collector-dashboard.json"]
  id = "/api/v1/dashboards/019fa952-8f72-7978-97f4-1e6d5d925444"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-system-monitoring/kubernetes-system-overview.json"]
  id = "/api/v1/dashboards/019fa952-9356-7ec3-a7b1-73fdb4de50ab"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-system-monitoring/kubernetes-kubelet.json"]
  id = "/api/v1/dashboards/019fa952-973a-7d4c-abda-7263c2fb6368"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-system-monitoring/kubernetes-etcd.json"]
  id = "/api/v1/dashboards/019fa952-9b22-7365-b244-c8af996274a1"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-infra-metrics/kubernetes-pod-metrics-overall.json"]
  id = "/api/v1/dashboards/019fa952-9f09-77c4-9e95-b476f280a869"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-infra-metrics/kubernetes-cluster-metrics.json"]
  id = "/api/v1/dashboards/019fa952-a2f6-7085-89c7-3b0eed3d676b"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-infra-metrics/kubernetes-pod-metrics-detailed.json"]
  id = "/api/v1/dashboards/019fa952-a6e2-7e38-941e-7e0833929a6a"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/nginx/nginx-ingress-request-handling-performance.json"]
  id = "/api/v1/dashboards/019fa952-aac7-7643-9954-9a9e0b0ef6ce"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-system-monitoring/kubernetes-apiserver.json"]
  id = "/api/v1/dashboards/019fa952-aea9-783e-adfb-71559d7c1a77"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-infra-metrics/host-metrics.json"]
  id = "/api/v1/dashboards/019fa952-b2ac-7b44-8d35-79d4cd781cc1"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-system-monitoring/kubernetes-controller-manager.json"]
  id = "/api/v1/dashboards/019fa952-b678-7776-a029-2907bea74680"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-infra-metrics/kubernetes-cronjobs.json"]
  id = "/api/v1/dashboards/019fa952-ba6e-7c7d-a892-ce39ce7a9531"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-infra-metrics/kubernetes-node-metrics-detailed.json"]
  id = "/api/v1/dashboards/019fa952-be54-7885-937e-1d47f2f17dd1"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-infra-metrics/kubernetes-pvc-metrics.json"]
  id = "/api/v1/dashboards/019fa952-c233-7d4b-bdf8-661772342193"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-infra-metrics/k8s-events-receiver.json"]
  id = "/api/v1/dashboards/019fa952-c61f-7079-b6d3-0380eb7a0780"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/nginx/ingress-nginx-controller.json"]
  id = "/api/v1/dashboards/019fa952-ca08-7cc0-81f9-e6621427aff7"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/hostmetrics/hostmetrics-k8s.json"]
  id = "/api/v1/dashboards/019fa952-ce56-76fd-a9a9-a96bae7a6456"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/cert-manager/cert-manager-dashboard.json"]
  id = "/api/v1/dashboards/019fa952-d1db-7cfa-9c62-f5b751251afd"
}
import {
  to = restapi_object.dashboard["signoz-dashboards/k8s-system-monitoring/kubernetes-scheduler.json"]
  id = "/api/v1/dashboards/019fa952-d5b9-7cb8-98d4-7deaa21924df"
}
