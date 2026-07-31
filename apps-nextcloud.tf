resource "kubernetes_namespace_v1" "nextcloud" {
  metadata {
    name = "nextcloud"
  }
}

resource "random_password" "nextcloud_admin" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "nextcloud_admin" {
  metadata {
    name      = "nextcloud-admin"
    namespace = kubernetes_namespace_v1.nextcloud.metadata[0].name
  }

  data = {
    "nextcloud-username" = "admin"
    "nextcloud-password" = random_password.nextcloud_admin.result
  }
}

resource "random_password" "nextcloud_db_root" {
  length  = 32
  special = false
}

resource "random_password" "nextcloud_db_user" {
  length  = 32
  special = false
}

resource "random_password" "nextcloud_db_replication" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "nextcloud_mariadb" {
  metadata {
    name      = "nextcloud-mariadb"
    namespace = kubernetes_namespace_v1.nextcloud.metadata[0].name
  }

  data = {
    "mariadb-root-password"        = random_password.nextcloud_db_root.result
    "mariadb-password"             = random_password.nextcloud_db_user.result
    "mariadb-replication-password" = random_password.nextcloud_db_replication.result
    "mariadb-username"             = "nextcloud"
  }
}

resource "random_password" "nextcloud_redis" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "nextcloud_redis" {
  metadata {
    name      = "nextcloud-redis"
    namespace = kubernetes_namespace_v1.nextcloud.metadata[0].name
  }

  data = {
    "redis-password" = random_password.nextcloud_redis.result
  }
}

resource "helm_release" "nextcloud" {
  name       = "nextcloud"
  repository = "https://nextcloud.github.io/helm/"
  chart      = "nextcloud"
  version    = "9.2.5"
  namespace  = kubernetes_namespace_v1.nextcloud.metadata[0].name

  set = [
    {
      name  = "phpClientHttpsFix.enabled"
      value = "true"
    },
    {
      name  = "nextcloud.existingSecret.enabled"
      value = "true"
    },
    {
      name  = "nextcloud.existingSecret.secretName"
      value = kubernetes_secret_v1.nextcloud_admin.metadata[0].name
    },
    {
      name  = "nextcloud.host"
      value = "nextcloud.vinnel.cloud"
    },
    {
      name  = "nextcloud.trustedDomains[0]"
      value = "nextcloud.vinnel.cloud"
    },
    {
      name  = "persistence.enabled"
      value = "true"
    },
    {
      name  = "persistence.storageClass"
      value = "ceph-block"
    },
    {
      name  = "persistence.accessMode"
      value = "ReadWriteOnce"
    },
    {
      name  = "persistence.size"
      value = "2Ti"
    },
    {
      name  = "internalDatabase.enabled"
      value = "false"
    },
    {
      name  = "externalDatabase.existingSecret.secretName"
      value = kubernetes_secret_v1.nextcloud_mariadb.metadata[0].name
    },
    {
      name  = "externalDatabase.existingSecret.usernameKey"
      value = "mariadb-username"
    },
    {
      name  = "externalDatabase.existingSecret.passwordKey"
      value = "mariadb-password"
    },
    {
      name  = "mariadb.enabled"
      value = "true"
    },
    {
      name  = "mariadb.auth.existingSecret"
      value = kubernetes_secret_v1.nextcloud_mariadb.metadata[0].name
    },
    {
      name  = "mariadb.primary.persistence.enabled"
      value = "true"
    },
    {
      name  = "mariadb.primary.persistence.storageClass"
      value = "ceph-block"
    },
    {
      name  = "mariadb.primary.persistence.size"
      value = "10Gi"
    },
    {
      name  = "redis.enabled"
      value = "true"
    },
    {
      name  = "redis.auth.existingSecret"
      value = kubernetes_secret_v1.nextcloud_redis.metadata[0].name
    },
    {
      name  = "redis.auth.existingSecretPasswordKey"
      value = "redis-password"
    }
  ]
}

resource "cloudflare_dns_record" "nextcloud_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "nextcloud.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "kubernetes_ingress_v1" "nextcloud_vinnel_cloud" {

  depends_on = [helm_release.nextcloud, helm_release.ingress_nginx]
  metadata {
    name      = "nextcloud-vinnel-cloud"
    namespace = kubernetes_namespace_v1.nextcloud.metadata[0].name
    annotations = merge(local.admin_framed_service_annotations["nextcloud"], {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer
    })
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["nextcloud.vinnel.cloud"]
      secret_name = "nextcloud-vinnel-cloud-tls"
    }

    rule {
      host = "nextcloud.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "nextcloud"
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "nextcloud_dav" {
  depends_on = [helm_release.nextcloud, kubernetes_ingress_v1.nextcloud_vinnel_cloud]
  metadata {
    name      = "nextcloud-dav"
    namespace = kubernetes_namespace_v1.nextcloud.metadata[0].name
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["nextcloud.vinnel.cloud"]
      secret_name = "nextcloud-vinnel-cloud-tls"
    }

    rule {
      host = "nextcloud.vinnel.cloud"
      http {
        dynamic "path" {
          for_each = [
            "/remote.php",
            "/public.php",
            "/status.php",
            "/ocs",
            "/ocm-provider",
            "/.well-known",
          ]
          iterator = prefix
          content {
            path      = prefix.value
            path_type = "Prefix"
            backend {
              service {
                name = "nextcloud"
                port {
                  number = 8080
                }
              }
            }
          }
        }
      }
    }
  }
}
