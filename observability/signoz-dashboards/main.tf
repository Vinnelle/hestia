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
    "signoz-dashboards/k8s-system-monitoring/kubernetes-kubelet.json"                  = "019fa952-973a-7d4c-abda-7263c2fb6368"
    "signoz-dashboards/k8s-system-monitoring/kubernetes-scheduler.json"                = "019fa952-d5b9-7cb8-98d4-7deaa21924df"
    "signoz-dashboards/k8s-system-monitoring/kubernetes-system-overview.json"          = "019fa952-9356-7ec3-a7b1-73fdb4de50ab"
    "signoz-dashboards/nginx/ingress-nginx-controller.json"                            = "019fa952-ca08-7cc0-81f9-e6621427aff7"
    "signoz-dashboards/nginx/nginx-ingress-request-handling-performance.json"          = "019fa952-aac7-7643-9954-9a9e0b0ef6ce"
    "signoz-dashboards/opentelemetry-collector/opentelemetry-collector-dashboard.json" = "019fa952-8f72-7978-97f4-1e6d5d925444"
  }
}

resource "signoz_dashboard" "dashboard" {
  for_each = local.signoz_dashboard_ids

  schema_version = "v6"
  name           = trim(replace(lower(jsondecode(file("${path.module}/../${each.key}")).title), "/[^a-z0-9]+/", "-"), "-")

  tags = [
    for t in jsondecode(file("${path.module}/../${each.key}")).tags : {
      key   = "tag"
      value = t
    }
  ]

  spec = {
    display = {
      name = jsondecode(file("${path.module}/../${each.key}")).title
    }
    layouts   = []
    panels    = {}
    variables = []
  }

  lifecycle {
    ignore_changes = [spec, tags, name]
  }
}

removed {
  from = restapi_object.dashboard

  lifecycle {
    destroy = false
  }
}

resource "signoz_dashboard" "service_status" {
  schema_version = "v6"
  name           = "service-status"

  tags = [
    { key = "tag", value = "kubernetes" },
    { key = "tag", value = "availability" },
  ]

  spec = {
    display = {
      name        = "Service Status"
      description = "Every workload's replica count against what it wants, and the restarts it took getting there"
    }
    links     = []
    variables = []

    panels = {
      "bf120719-8534-4582-8d08-706eb360fc9c" = {
        kind = "Panel"
        spec = {
          display = { name = "Deployment replicas available" }
          links   = []
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                legend = { position = "bottom", mode = "list" }
              }
            }
          }
          queries = [{
            kind = "time_series"
            spec = {
              name = "A"
              plugin = {
                builder_query = {
                  kind = "signoz/BuilderQuery"
                  spec = {
                    metrics = {
                      name          = "A"
                      step_interval = "60"
                      signal        = "metrics"
                      aggregations = [{
                        metric_name       = "k8s.deployment.available"
                        time_aggregation  = "avg"
                        space_aggregation = "sum"
                        reduce_to         = "last"
                      }]
                      filter   = { expression = "" }
                      having   = { expression = "" }
                      group_by = [{ name = "k8s.deployment.name", field_context = "attribute", field_data_type = "string" }]
                      legend   = "{{k8s.deployment.name}}"
                    }
                  }
                }
              }
            }
          }]
        }
      }

      "69e99cd6-cc3b-4d57-8bd7-6bf44a34b667" = {
        kind = "Panel"
        spec = {
          display = { name = "Deployment replicas desired" }
          links   = []
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                legend = { position = "bottom", mode = "list" }
              }
            }
          }
          queries = [{
            kind = "time_series"
            spec = {
              name = "A"
              plugin = {
                builder_query = {
                  kind = "signoz/BuilderQuery"
                  spec = {
                    metrics = {
                      name          = "A"
                      step_interval = "60"
                      signal        = "metrics"
                      aggregations = [{
                        metric_name       = "k8s.deployment.desired"
                        time_aggregation  = "avg"
                        space_aggregation = "sum"
                        reduce_to         = "last"
                      }]
                      filter   = { expression = "" }
                      having   = { expression = "" }
                      group_by = [{ name = "k8s.deployment.name", field_context = "attribute", field_data_type = "string" }]
                      legend   = "{{k8s.deployment.name}}"
                    }
                  }
                }
              }
            }
          }]
        }
      }

      "60fd2dff-2f15-4049-8d8a-feb0ecc6b1ee" = {
        kind = "Panel"
        spec = {
          display = { name = "StatefulSet pods ready" }
          links   = []
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                legend = { position = "bottom", mode = "list" }
              }
            }
          }
          queries = [{
            kind = "time_series"
            spec = {
              name = "A"
              plugin = {
                builder_query = {
                  kind = "signoz/BuilderQuery"
                  spec = {
                    metrics = {
                      name          = "A"
                      step_interval = "60"
                      signal        = "metrics"
                      aggregations = [{
                        metric_name       = "k8s.statefulset.ready_pods"
                        time_aggregation  = "avg"
                        space_aggregation = "sum"
                        reduce_to         = "last"
                      }]
                      filter   = { expression = "" }
                      having   = { expression = "" }
                      group_by = [{ name = "k8s.statefulset.name", field_context = "attribute", field_data_type = "string" }]
                      legend   = "{{k8s.statefulset.name}}"
                    }
                  }
                }
              }
            }
          }]
        }
      }

      "bb71a87c-3611-4fca-b903-b51ef1cb64dc" = {
        kind = "Panel"
        spec = {
          display = { name = "Container restarts" }
          links   = []
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                legend = { position = "bottom", mode = "list" }
              }
            }
          }
          queries = [{
            kind = "time_series"
            spec = {
              name = "A"
              plugin = {
                builder_query = {
                  kind = "signoz/BuilderQuery"
                  spec = {
                    metrics = {
                      name          = "A"
                      step_interval = "60"
                      signal        = "metrics"
                      aggregations = [{
                        metric_name       = "k8s.container.restarts"
                        time_aggregation  = "max"
                        space_aggregation = "sum"
                        reduce_to         = "last"
                      }]
                      filter   = { expression = "" }
                      having   = { expression = "" }
                      group_by = [{ name = "k8s.pod.name", field_context = "attribute", field_data_type = "string" }]
                      legend   = "{{k8s.pod.name}}"
                    }
                  }
                }
              }
            }
          }]
        }
      }
    }

    layouts = [{
      grid = {
        kind = "Grid"
        spec = {
          display = {
            title    = "Workloads"
            collapse = { open = true }
          }
          items = [
            { x = 0, y = 0, width = 6, height = 6, content = { ref = "#/spec/panels/bf120719-8534-4582-8d08-706eb360fc9c" } },
            { x = 6, y = 0, width = 6, height = 6, content = { ref = "#/spec/panels/69e99cd6-cc3b-4d57-8bd7-6bf44a34b667" } },
            { x = 0, y = 6, width = 6, height = 6, content = { ref = "#/spec/panels/60fd2dff-2f15-4049-8d8a-feb0ecc6b1ee" } },
            { x = 6, y = 6, width = 6, height = 6, content = { ref = "#/spec/panels/bb71a87c-3611-4fca-b903-b51ef1cb64dc" } },
          ]
        }
      }
    }]
  }
}

resource "signoz_dashboard" "container_security" {
  schema_version = "v6"
  name           = "container-security"

  tags = [
    { key = "tag", value = "security" },
    { key = "tag", value = "trivy" },
  ]

  spec = {
    display = {
      name        = "Container Security"
      description = "What trivy-operator finds in the images this cluster is actually running"
    }
    links     = []
    variables = []

    panels = {
      "1a075a04-efc3-4ad4-9a25-8db6da78f62e" = {
        kind = "Panel"
        spec = {
          display = { name = "Critical vulnerabilities" }
          links   = []
          plugin = {
            number_panel = {
              kind = "signoz/NumberPanel"
              spec = {
                formatting = { decimal_precision = "0" }
              }
            }
          }
          queries = [{
            kind = "scalar"
            spec = {
              name = "A"
              plugin = {
                builder_query = {
                  kind = "signoz/BuilderQuery"
                  spec = {
                    metrics = {
                      name          = "A"
                      step_interval = "60"
                      signal        = "metrics"
                      aggregations = [{
                        metric_name       = "trivy_image_vulnerabilities"
                        time_aggregation  = "max"
                        space_aggregation = "sum"
                        reduce_to         = "last"
                      }]
                      filter = { expression = "severity = 'Critical'" }
                      having = { expression = "" }
                      legend = "critical"
                    }
                  }
                }
              }
            }
          }]
        }
      }

      "5c019d7e-c7af-4d52-964c-cd7bd888d31e" = {
        kind = "Panel"
        spec = {
          display = { name = "Exposed secrets in images" }
          links   = []
          plugin = {
            number_panel = {
              kind = "signoz/NumberPanel"
              spec = {
                formatting = { decimal_precision = "0" }
              }
            }
          }
          queries = [{
            kind = "scalar"
            spec = {
              name = "A"
              plugin = {
                builder_query = {
                  kind = "signoz/BuilderQuery"
                  spec = {
                    metrics = {
                      name          = "A"
                      step_interval = "60"
                      signal        = "metrics"
                      aggregations = [{
                        metric_name       = "trivy_image_exposedsecrets"
                        time_aggregation  = "max"
                        space_aggregation = "sum"
                        reduce_to         = "last"
                      }]
                      filter = { expression = "" }
                      having = { expression = "" }
                      legend = "secrets"
                    }
                  }
                }
              }
            }
          }]
        }
      }

      "0ad09f7a-b2e4-4559-8879-c588abf2ab66" = {
        kind = "Panel"
        spec = {
          display = { name = "Vulnerabilities by severity" }
          links   = []
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                legend = { position = "bottom", mode = "list" }
              }
            }
          }
          queries = [{
            kind = "time_series"
            spec = {
              name = "A"
              plugin = {
                builder_query = {
                  kind = "signoz/BuilderQuery"
                  spec = {
                    metrics = {
                      name          = "A"
                      step_interval = "60"
                      signal        = "metrics"
                      aggregations = [{
                        metric_name       = "trivy_image_vulnerabilities"
                        time_aggregation  = "max"
                        space_aggregation = "sum"
                        reduce_to         = "last"
                      }]
                      filter   = { expression = "" }
                      having   = { expression = "" }
                      group_by = [{ name = "severity", field_context = "attribute", field_data_type = "string" }]
                      legend   = "{{severity}}"
                    }
                  }
                }
              }
            }
          }]
        }
      }

      "643a1b48-6df6-46ab-b8e4-5fd0e0878392" = {
        kind = "Panel"
        spec = {
          display = { name = "Critical vulnerabilities by namespace" }
          links   = []
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                legend = { position = "bottom", mode = "list" }
              }
            }
          }
          queries = [{
            kind = "time_series"
            spec = {
              name = "A"
              plugin = {
                builder_query = {
                  kind = "signoz/BuilderQuery"
                  spec = {
                    metrics = {
                      name          = "A"
                      step_interval = "60"
                      signal        = "metrics"
                      aggregations = [{
                        metric_name       = "trivy_image_vulnerabilities"
                        time_aggregation  = "max"
                        space_aggregation = "sum"
                        reduce_to         = "last"
                      }]
                      filter   = { expression = "severity = 'Critical'" }
                      having   = { expression = "" }
                      group_by = [{ name = "namespace", field_context = "attribute", field_data_type = "string" }]
                      legend   = "{{namespace}}"
                    }
                  }
                }
              }
            }
          }]
        }
      }
    }

    layouts = [{
      grid = {
        kind = "Grid"
        spec = {
          display = {
            title    = "Findings"
            collapse = { open = true }
          }
          items = [
            { x = 0, y = 0, width = 3, height = 4, content = { ref = "#/spec/panels/1a075a04-efc3-4ad4-9a25-8db6da78f62e" } },
            { x = 3, y = 0, width = 3, height = 4, content = { ref = "#/spec/panels/5c019d7e-c7af-4d52-964c-cd7bd888d31e" } },
            { x = 0, y = 4, width = 6, height = 6, content = { ref = "#/spec/panels/0ad09f7a-b2e4-4559-8879-c588abf2ab66" } },
            { x = 6, y = 4, width = 6, height = 6, content = { ref = "#/spec/panels/643a1b48-6df6-46ab-b8e4-5fd0e0878392" } },
          ]
        }
      }
    }]
  }
}
