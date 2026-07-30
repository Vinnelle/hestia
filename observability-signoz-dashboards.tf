locals {
  signoz_dashboard_ids = {
    "signoz-dashboards/cert-manager/cert-manager-dashboard.json"                       = "019fa952-d1db-7cfa-9c62-f5b751251afd"
    "signoz-dashboards/chaos-mesh/chaos-mesh.json"                                     = "019fab9d-addc-754e-8d2b-ace826af8c9b"
    "signoz-dashboards/k8s-infra-metrics/host-metrics.json"                            = "019fa952-b2ac-7b44-8d35-79d4cd781cc1"
    "signoz-dashboards/k8s-infra-metrics/k8s-events-receiver.json"                     = "019fa952-c61f-7079-b6d3-0380eb7a0780"
    "signoz-dashboards/k8s-infra-metrics/kubernetes-cluster-metrics.json"              = "019fa952-a2f6-7085-89c7-3b0eed3d676b"
    "signoz-dashboards/k8s-infra-metrics/kubernetes-cronjobs.json"                     = "019fa952-ba6e-7c7d-a892-ce39ce7a9531"
    "signoz-dashboards/k8s-infra-metrics/kubernetes-node-metrics-detailed.json"        = "019fa952-be54-7885-937e-1d47f2f17dd1"
    "signoz-dashboards/k8s-infra-metrics/kubernetes-node-metrics-overall.json"         = "019fa952-879b-78da-be0f-b0288e79fe56"
    "signoz-dashboards/k8s-infra-metrics/kubernetes-pod-metrics-detailed.json"         = "019fa952-a6e2-7e38-941e-7e0833929a6a"
    "signoz-dashboards/k8s-infra-metrics/kubernetes-pod-metrics-overall.json"          = "019fa952-9f09-77c4-9e95-b476f280a869"
    "signoz-dashboards/k8s-infra-metrics/kubernetes-pvc-metrics.json"                  = "019fa952-c233-7d4b-bdf8-661772342193"
    "signoz-dashboards/k8s-system-monitoring/kubernetes-apiserver.json"                = "019fa952-aea9-783e-adfb-71559d7c1a77"
    "signoz-dashboards/k8s-system-monitoring/kubernetes-controller-manager.json"       = "019fa952-b678-7776-a029-2907bea74680"
    "signoz-dashboards/k8s-system-monitoring/kubernetes-coredns.json"                  = "019fa952-84e5-7a3b-a52a-230c228d9229"
    "signoz-dashboards/k8s-system-monitoring/kubernetes-etcd.json"                     = "019fa952-9b22-7365-b244-c8af996274a1"
    "signoz-dashboards/k8s-system-monitoring/kubernetes-kube-proxy.json"               = "019fa952-8b82-705e-83d3-314874c02cbc"
    "signoz-dashboards/k8s-system-monitoring/kubernetes-kubelet.json"                  = "019fa952-973a-7d4c-abda-7263c2fb6368"
    "signoz-dashboards/k8s-system-monitoring/kubernetes-scheduler.json"                = "019fa952-d5b9-7cb8-98d4-7deaa21924df"
    "signoz-dashboards/k8s-system-monitoring/kubernetes-system-overview.json"          = "019fa952-9356-7ec3-a7b1-73fdb4de50ab"
    "signoz-dashboards/nginx/ingress-nginx-controller.json"                            = "019fa952-ca08-7cc0-81f9-e6621427aff7"
    "signoz-dashboards/nginx/nginx-ingress-request-handling-performance.json"          = "019fa952-aac7-7643-9954-9a9e0b0ef6ce"
    "signoz-dashboards/opentelemetry-collector/opentelemetry-collector-dashboard.json" = "019fa952-8f72-7978-97f4-1e6d5d925444"
  }
}

resource "signoz_dashboard" "dashboard" {
  depends_on = [helm_release.signoz]

  for_each = local.signoz_dashboard_ids

  schema_version = "v6"
  name           = jsondecode(file("${path.module}/${each.key}")).title

  tags = [
    for t in jsondecode(file("${path.module}/${each.key}")).tags : {
      key   = "tag"
      value = t
    }
  ]

  spec = {
    display = {
      name = jsondecode(file("${path.module}/${each.key}")).title
    }
    layouts   = []
    panels    = {}
    variables = []
  }

  lifecycle {
    ignore_changes = [spec, tags, name]
  }
}

import {
  for_each = local.signoz_dashboard_ids
  to       = signoz_dashboard.dashboard[each.key]
  id       = each.value
}

removed {
  from = restapi_object.dashboard

  lifecycle {
    destroy = false
  }
}
