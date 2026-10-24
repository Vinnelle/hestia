locals {
  tempo_config = {
    stream_over_http_enabled = true
    server = {
      http_listen_port = 3200
    }
    distributor = {
      receivers = {
        otlp = {
          protocols = {
            grpc = { endpoint = "0.0.0.0:4317" }
            http = { endpoint = "0.0.0.0:4318" }
          }
        }
      }
    }
    compactor = {
      compaction = {
        block_retention = "168h"
      }
    }
    metrics_generator = {
      registry = {
        external_labels = { source = "tempo" }
      }
      storage = {
        path = "/var/tempo/generator/wal"
        remote_write = [{
          url            = "http://vmsingle-vm.${local.namespace}.svc.cluster.local:8428/api/v1/write"
          send_exemplars = true
        }]
      }
      traces_storage = {
        path = "/var/tempo/generator/traces"
      }
      processor = {
        local_blocks = { flush_to_storage = true }
      }
    }
    storage = {
      trace = {
        backend = "local"
        local   = { path = "/var/tempo/traces" }
        wal     = { path = "/var/tempo/wal" }
      }
    }
    overrides = {
      defaults = {
        metrics_generator = {
          processors = ["service-graphs", "span-metrics", "local-blocks"]
        }
      }
    }
    usage_report = {
      reporting_enabled = false
    }
  }
}

resource "kubernetes_config_map_v1" "tempo" {
  metadata {
    name      = "tempo"
    namespace = local.namespace
  }

  data = {
    "tempo.yaml" = yamlencode(local.tempo_config)
  }
}

resource "kubernetes_service_v1" "tempo" {
  metadata {
    name      = "tempo"
    namespace = local.namespace
  }

  spec {
    selector = { app = "tempo" }

    port {
      name        = "http"
      port        = 3200
      target_port = 3200
    }
    port {
      name        = "otlp-grpc"
      port        = 4317
      target_port = 4317
    }
    port {
      name        = "otlp-http"
      port        = 4318
      target_port = 4318
    }
  }
}

resource "kubernetes_stateful_set_v1" "tempo" {
  metadata {
    name      = "tempo"
    namespace = local.namespace
  }

  spec {
    service_name = kubernetes_service_v1.tempo.metadata[0].name
    replicas     = 1

    selector {
      match_labels = { app = "tempo" }
    }

    template {
      metadata {
        labels = { app = "tempo" }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "3200"
          "checksum/config"      = sha256(kubernetes_config_map_v1.tempo.data["tempo.yaml"])
        }
      }

      spec {
        security_context {
          run_as_user     = 10001
          run_as_group    = 10001
          run_as_non_root = true
          fs_group        = 10001
        }

        container {
          name  = "tempo"
          image = "grafana/tempo:2.10.10"
          args  = ["-config.file=/conf/tempo.yaml"]

          port {
            name           = "http"
            container_port = 3200
          }
          port {
            name           = "otlp-grpc"
            container_port = 4317
          }
          port {
            name           = "otlp-http"
            container_port = 4318
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 3200
            }
            initial_delay_seconds = 15
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "256Mi"
            }
            limits = {
              memory = "2Gi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/conf"
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/tempo"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.tempo.metadata[0].name
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "local-path-hostpath"
        resources {
          requests = {
            storage = "10Gi"
          }
        }
      }
    }
  }
}
