
resource "kubernetes_namespace_v1" "harness" {
  metadata {
    name = "harness"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "cloudflare_dns_record" "harness_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "harness.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "random_password" "harness_postgres" {
  length  = 24
  special = false
}

resource "random_password" "harness_admin_password" {
  length = 32
}

locals {
  harness_postgres_dsn = "host=${kubernetes_service_v1.harness_postgres.metadata[0].name}.${kubernetes_namespace_v1.harness.metadata[0].name}.svc.cluster.local port=5432 sslmode=disable dbname=harness user=harness password=${random_password.harness_postgres.result}"

  harness_config_hash = sha256(join("", [
    random_password.harness_postgres.result,
    random_password.harness_admin_password.result,
  ]))
}

resource "kubernetes_secret_v1" "harness_postgres" {
  metadata {
    name      = "harness-postgres"
    namespace = kubernetes_namespace_v1.harness.metadata[0].name
  }
  data = {
    POSTGRES_USER     = "harness"
    POSTGRES_PASSWORD = random_password.harness_postgres.result
    POSTGRES_DB       = "harness"
  }
}

resource "kubernetes_secret_v1" "registry_dockerconfig_harness" {
  metadata {
    name      = "registry-dockerconfig"
    namespace = kubernetes_namespace_v1.harness.metadata[0].name
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "registry.vinnel.cloud" = {
          username = harbor_robot_account.ci.full_name
          password = random_password.harbor_robot.result
          auth     = base64encode("${harbor_robot_account.ci.full_name}:${random_password.harbor_robot.result}")
        }
      }
    })
  }
}

resource "kubernetes_persistent_volume_claim_v1" "harness_postgres_data" {
  metadata {
    name      = "harness-postgres-data-pvc"
    namespace = kubernetes_namespace_v1.harness.metadata[0].name
    annotations = {
      "volumeType" = "hostPath"
    }
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_persistent_volume_claim_v1" "harness_data" {
  metadata {
    name      = "harness-data-pvc"
    namespace = kubernetes_namespace_v1.harness.metadata[0].name
    annotations = {
      "volumeType" = "hostPath"
    }
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "50Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_deployment_v1" "harness_postgres" {
  metadata {
    name      = "harness-postgres"
    namespace = kubernetes_namespace_v1.harness.metadata[0].name
    labels = {
      app = "harness-postgres"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "harness-postgres"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "harness-postgres"
        }
        annotations = {
          "config-hash" = random_password.harness_postgres.result
        }
      }

      spec {
        enable_service_links = false

        container {
          name  = "postgres"
          image = "postgres:17@sha256:7958605b474b3d264a969cb3a123d6aa00ad1e1fe9da8a69984dabb704d93317"

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.harness_postgres.metadata[0].name
            }
          }

          port {
            name           = "postgres"
            container_port = 5432
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }

          readiness_probe {
            tcp_socket {
              port = "postgres"
            }
            period_seconds  = 10
            timeout_seconds = 5
          }

          liveness_probe {
            tcp_socket {
              port = "postgres"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.harness_postgres_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubectl_manifest" "harness_postgres_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.harness_postgres]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "harness-postgres"
    namespace   = kubernetes_namespace_v1.harness.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.harness_postgres.metadata[0].name
    update_mode = "Initial"
    container_policies = [
      { container_name = "postgres", min_memory = "256Mi", max_memory = "1Gi" },
    ]
  })
}

resource "kubernetes_service_v1" "harness_postgres" {
  metadata {
    name      = "harness-postgres"
    namespace = kubernetes_namespace_v1.harness.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "harness-postgres"
    }
    port {
      port        = 5432
      target_port = "postgres"
    }
  }
}

resource "kubernetes_deployment_v1" "harness" {
  depends_on = [kubernetes_service_v1.harness_postgres]

  metadata {
    name      = "harness"
    namespace = kubernetes_namespace_v1.harness.metadata[0].name
    labels = {
      app = "harness"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "harness"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "harness"
        }
        annotations = {
          "config-hash" = local.harness_config_hash
        }
      }

      spec {
        enable_service_links = false

        host_aliases {
          ip        = var.node_ip
          hostnames = ["registry.vinnel.cloud"]
        }

        image_pull_secrets {
          name = kubernetes_secret_v1.registry_dockerconfig_harness.metadata[0].name
        }

        container {
          name  = "harness"
          image = "harness/harness:3.3.0@sha256:c1bd76817ad7d2e7d78827653a54c55d4aec87c2777a586ebbad1ed01fc9e83f"

          env {
            name  = "GITNESS_URL_BASE"
            value = "https://harness.vinnel.cloud"
          }
          env {
            name  = "GITNESS_DATABASE_DRIVER"
            value = "postgres"
          }
          env {
            name  = "GITNESS_DATABASE_DATASOURCE"
            value = local.harness_postgres_dsn
          }
          env {
            name  = "GITNESS_USER_SIGNUP_ENABLED"
            value = "false"
          }
          env {
            name  = "GITNESS_PRINCIPAL_ADMIN_EMAIL"
            value = var.acme_email_vin_moe
          }
          env {
            name  = "GITNESS_PRINCIPAL_ADMIN_PASSWORD"
            value = random_password.harness_admin_password.result
          }
          env {
            name  = "DOCKER_HOST"
            value = "unix:///var/run/docker.sock"
          }

          port {
            name           = "http"
            container_port = 3000
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "2000m"
              memory = "2Gi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          volume_mount {
            name       = "docker-socket"
            mount_path = "/var/run"
          }

          volume_mount {
            name       = "docker-config"
            mount_path = "/root/.docker"
            read_only  = true
          }

          readiness_probe {
            tcp_socket {
              port = "http"
            }
            period_seconds  = 10
            timeout_seconds = 5
          }

          liveness_probe {
            tcp_socket {
              port = "http"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        container {
          name  = "dind"
          image = "docker:dind@sha256:e8faad5a8dc5279dff929afc5449f2791736912fff9f99351d742db2fad01b4c"

          security_context {
            privileged = true
          }

          env {
            name  = "DOCKER_TLS_CERTDIR"
            value = ""
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "4000m"
              memory = "8Gi"
            }
          }

          volume_mount {
            name       = "docker-socket"
            mount_path = "/var/run"
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.harness_data.metadata[0].name
          }
        }

        volume {
          name = "docker-socket"
          empty_dir {}
        }

        volume {
          name = "docker-config"
          secret {
            secret_name = kubernetes_secret_v1.registry_dockerconfig_harness.metadata[0].name
            items {
              key  = ".dockerconfigjson"
              path = "config.json"
            }
          }
        }
      }
    }
  }
}

resource "kubectl_manifest" "harness_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.harness]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "harness"
    namespace   = kubernetes_namespace_v1.harness.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.harness.metadata[0].name
    update_mode = "Initial"
    container_policies = [
      { container_name = "harness", min_memory = "512Mi", max_memory = "2Gi" },
      { container_name = "dind", min_memory = "512Mi", max_memory = "8Gi" },
    ]
  })
}

resource "kubernetes_network_policy_v1" "harness_egress" {
  depends_on = [helm_release.cilium, kubernetes_deployment_v1.harness]

  metadata {
    name      = "harness-egress"
    namespace = kubernetes_namespace_v1.harness.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = { "k8s-app" = "kube-dns" }
        }
      }
      ports {
        port     = 53
        protocol = "UDP"
      }
      ports {
        port     = 53
        protocol = "TCP"
      }
    }

    egress {
      to {
        pod_selector {
          match_labels = { app = "harness-postgres" }
        }
      }
      ports {
        port     = 5432
        protocol = "TCP"
      }
    }

    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
          except = [
            "10.244.0.0/16",
            "10.96.0.0/12",
          ]
        }
      }
    }
  }
}

resource "kubectl_manifest" "harness_egress_host" {
  depends_on = [helm_release.cilium, kubernetes_deployment_v1.harness]
  yaml_body = yamlencode({
    apiVersion = "cilium.io/v2"
    kind       = "CiliumNetworkPolicy"
    metadata = {
      name      = "harness-egress-host"
      namespace = kubernetes_namespace_v1.harness.metadata[0].name
    }
    spec = {
      endpointSelector = {}
      egress = [
        { toEntities = ["host"] }
      ]
    }
  })
}

resource "kubernetes_service_v1" "harness" {
  metadata {
    name      = "harness"
    namespace = kubernetes_namespace_v1.harness.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "harness"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_ingress_v1" "harness_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx, kubernetes_deployment_v1.harness]
  metadata {
    name      = "harness-vinnel-cloud"
    namespace = kubernetes_namespace_v1.harness.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"              = local.vinnel_cloud_cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-body-size" = "0"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["harness.vinnel.cloud"]
      secret_name = "harness-vinnel-cloud-tls"
    }

    rule {
      host = "harness.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.harness.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
