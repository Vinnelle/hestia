
resource "kubernetes_namespace_v1" "seaweedfs" {
  metadata {
    name = "seaweedfs"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "cloudflare_dns_record" "s3_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "s3.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "seaweed_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "seaweed.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "random_password" "seaweedfs_s3_access_key" {
  length  = 20
  special = false
}

resource "random_password" "seaweedfs_s3_secret_key" {
  length  = 40
  special = false
}

resource "random_password" "seaweedfs_disk_encryption_key" {
  length  = 64
  special = false
}

locals {
  seaweedfs_s3_config_json = jsonencode({
    identities = [
      {
        name = "admin"
        credentials = [
          {
            accessKey = random_password.seaweedfs_s3_access_key.result
            secretKey = random_password.seaweedfs_s3_secret_key.result
          }
        ]
        actions = ["Admin", "Read", "Write", "List", "Tagging"]
      }
    ]
  })

  seaweedfs_start_sh = <<-EOT
    #!/bin/sh
    set -e
    weed server -dir=/data,/data-hdd1,/data-hdd2,/data-ssd -volume.max=7,0,0,0 -volume.disk=hdd,hdd,hdd,ssd -filer.disk=hdd -s3 -s3.config=/etc/seaweedfs/s3.json -filer -ip.bind=0.0.0.0 &
    SERVER_PID=$!
    # `weed shell` exits 0 even when the command inside it fails, so every wait
    # and check here tests an observable effect, never an exit status. Wait on
    # the filer's *gRPC* port (18888), which comes up about a second after its
    # HTTP port (8888) -- fs.configure needs gRPC, and the old loop waited on
    # HTTP only, so all three commands below fired into a filer that could not
    # yet serve them.
    i=0
    while [ "$i" -lt 60 ]; do
      if echo "fs.configure" | weed shell -filer=localhost:8888 2>&1 | grep -q '"locations"'; then
        break
      fi
      i=$((i + 1))
      sleep 2
    done
    echo "s3.bucket.create -name nextcloud" | weed shell -filer=localhost:8888 2>&1
    echo "s3.bucket.create -name velero" | weed shell -filer=localhost:8888 2>&1
    echo "s3.bucket.create -name harbor" | weed shell -filer=localhost:8888 2>&1
    # No -collection here: an S3 bucket is already 1:1 with a collection named
    # after it, and passing one makes the whole command fail with
    # "one s3 bucket goes to one collection and not customizable".
    echo "fs.configure -locationPrefix=/buckets/nextcloud/ -disk=ssd -apply" | weed shell -filer=localhost:8888 2>&1
    echo "fs.configure" | weed shell -filer=localhost:8888 2>&1 | grep -q "/buckets/nextcloud/" ||
      echo "WARNING: seaweedfs ssd tier rule did not apply; new writes will land on hdd" >&2
    wait "$SERVER_PID"
  EOT

  seaweedfs_tier_move_sh = <<-EOT
    #!/bin/sh
    set -e
    echo "volume.tier.move -fromDiskType=ssd -toDiskType=hdd -quietFor=24h -fullPercent=95" | weed shell -master=seaweedfs.seaweedfs.svc.cluster.local:9333
  EOT
}

resource "kubernetes_secret_v1" "seaweedfs_s3_config" {
  metadata {
    name      = "seaweedfs-s3-config"
    namespace = kubernetes_namespace_v1.seaweedfs.metadata[0].name
  }
  data = {
    "s3.json" = local.seaweedfs_s3_config_json
  }
}

resource "kubernetes_config_map_v1" "seaweedfs_scripts" {
  metadata {
    name      = "seaweedfs-scripts"
    namespace = kubernetes_namespace_v1.seaweedfs.metadata[0].name
  }
  data = {
    "start.sh" = local.seaweedfs_start_sh
  }
}

resource "kubernetes_persistent_volume_claim_v1" "seaweedfs_data" {
  metadata {
    name      = "seaweedfs-data-pvc"
    namespace = kubernetes_namespace_v1.seaweedfs.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "200Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_deployment_v1" "seaweedfs" {
  metadata {
    name      = "seaweedfs"
    namespace = kubernetes_namespace_v1.seaweedfs.metadata[0].name
    labels = {
      app = "seaweedfs"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "seaweedfs"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "seaweedfs"
        }
        annotations = {
          "seaweedfs-config-hash" = sha256("${local.seaweedfs_s3_config_json}${local.seaweedfs_start_sh}")
        }
      }

      spec {
        enable_service_links = false

        container {
          name    = "seaweedfs"
          image   = "chrislusf/seaweedfs:4.41"
          command = ["/bin/sh", "/scripts/start.sh"]

          port {
            name           = "master"
            container_port = 9333
          }

          port {
            name           = "volume"
            container_port = 8080
          }

          port {
            name           = "filer"
            container_port = 8888
          }

          port {
            name           = "filer-grpc"
            container_port = 18888
          }

          port {
            name           = "s3"
            container_port = 8333
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          volume_mount {
            name       = "hdd1"
            mount_path = "/data-hdd1"
          }

          volume_mount {
            name       = "hdd2"
            mount_path = "/data-hdd2"
          }

          volume_mount {
            name       = "ssd"
            mount_path = "/data-ssd"
          }

          volume_mount {
            name       = "s3-config"
            mount_path = "/etc/seaweedfs/s3.json"
            sub_path   = "s3.json"
            read_only  = true
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
            read_only  = true
          }

          readiness_probe {
            tcp_socket {
              port = "filer"
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 12
          }

          liveness_probe {
            tcp_socket {
              port = "filer"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.seaweedfs_data.metadata[0].name
          }
        }

        volume {
          name = "hdd1"
          host_path {
            path = "/var/mnt/seaweed-hdd1"
            type = "Directory"
          }
        }

        volume {
          name = "hdd2"
          host_path {
            path = "/var/mnt/seaweed-hdd2"
            type = "Directory"
          }
        }

        volume {
          name = "ssd"
          host_path {
            path = "/var/mnt/seaweed-ssd"
            type = "Directory"
          }
        }

        volume {
          name = "s3-config"
          secret {
            secret_name = kubernetes_secret_v1.seaweedfs_s3_config.metadata[0].name
          }
        }

        volume {
          name = "scripts"
          config_map {
            name         = kubernetes_config_map_v1.seaweedfs_scripts.metadata[0].name
            default_mode = "0555"
          }
        }
      }
    }
  }
}

resource "kubernetes_cron_job_v1" "seaweedfs_tier_move" {
  metadata {
    name      = "seaweedfs-tier-move"
    namespace = kubernetes_namespace_v1.seaweedfs.metadata[0].name
  }

  spec {
    schedule                      = "0 4 * * *"
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {}
      spec {
        template {
          metadata {}
          spec {
            restart_policy = "OnFailure"
            container {
              name    = "tier-move"
              image   = "chrislusf/seaweedfs:4.41"
              command = ["/bin/sh", "-c", local.seaweedfs_tier_move_sh]
            }
          }
        }
      }
    }
  }
}

module "seaweedfs_vpa" {
  source = "./modules/vpa"

  depends_on = [helm_release.vpa, kubernetes_deployment_v1.seaweedfs]

  name        = "seaweedfs"
  namespace   = kubernetes_namespace_v1.seaweedfs.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.seaweedfs.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "seaweedfs", min_memory = "128Mi", max_memory = "1Gi" },
  ]
}

resource "kubernetes_service_v1" "seaweedfs" {
  metadata {
    name      = "seaweedfs"
    namespace = kubernetes_namespace_v1.seaweedfs.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "seaweedfs"
    }
    port {
      name        = "master"
      port        = 9333
      target_port = "master"
    }
    port {
      name        = "volume"
      port        = 8080
      target_port = "volume"
    }
    port {
      name        = "filer"
      port        = 8888
      target_port = "filer"
    }
    port {
      name        = "filer-grpc"
      port        = 18888
      target_port = "filer-grpc"
    }
    port {
      name        = "s3"
      port        = 8333
      target_port = "s3"
    }
  }
}

resource "kubernetes_ingress_v1" "s3_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "s3-vinnel-cloud"
    namespace = kubernetes_namespace_v1.seaweedfs.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"              = local.vinnel_cloud_cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-body-size" = "0"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["s3.vinnel.cloud"]
      secret_name = "s3-vinnel-cloud-tls"
    }

    rule {
      host = "s3.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.seaweedfs.metadata[0].name
              port {
                number = 8333
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "seaweed_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "seaweed-vinnel-cloud"
    namespace = kubernetes_namespace_v1.seaweedfs.metadata[0].name
    annotations = merge(local.admin_framed_service_annotations["seaweed"], {
      "cert-manager.io/cluster-issuer"              = local.vinnel_cloud_cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-body-size" = "0"
    })
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["seaweed.vinnel.cloud"]
      secret_name = "seaweed-vinnel-cloud-tls"
    }

    rule {
      host = "seaweed.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.seaweedfs.metadata[0].name
              port {
                number = 8888
              }
            }
          }
        }
      }
    }
  }
}
