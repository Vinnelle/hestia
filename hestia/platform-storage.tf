
resource "kubernetes_namespace_v1" "local_path_storage" {
  metadata {
    name = "local-path-storage"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "kubernetes_service_account_v1" "local_path_provisioner" {
  metadata {
    name      = "local-path-provisioner-service-account"
    namespace = kubernetes_namespace_v1.local_path_storage.metadata[0].name
  }
}

resource "kubernetes_role_v1" "local_path_provisioner" {
  metadata {
    name      = "local-path-provisioner-role"
    namespace = kubernetes_namespace_v1.local_path_storage.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch", "create", "patch", "update", "delete"]
  }
}

resource "kubernetes_cluster_role_v1" "local_path_provisioner" {
  metadata {
    name = "local-path-provisioner-role"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "persistentvolumeclaims", "configmaps", "pods", "pods/log"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["persistentvolumes"]
    verbs      = ["get", "list", "watch", "create", "patch", "update", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding_v1" "local_path_provisioner" {
  metadata {
    name      = "local-path-provisioner-bind"
    namespace = kubernetes_namespace_v1.local_path_storage.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.local_path_provisioner.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.local_path_provisioner.metadata[0].name
    namespace = kubernetes_namespace_v1.local_path_storage.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding_v1" "local_path_provisioner" {
  metadata {
    name = "local-path-provisioner-bind"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.local_path_provisioner.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.local_path_provisioner.metadata[0].name
    namespace = kubernetes_namespace_v1.local_path_storage.metadata[0].name
  }
}

resource "kubernetes_config_map_v1" "local_path_config" {
  metadata {
    name      = "local-path-config"
    namespace = kubernetes_namespace_v1.local_path_storage.metadata[0].name
  }

  data = {
    "config.json"    = file("${path.module}/local-path-provisioner/config.json")
    "setup"          = file("${path.module}/local-path-provisioner/setup")
    "teardown"       = file("${path.module}/local-path-provisioner/teardown")
    "helperPod.yaml" = file("${path.module}/local-path-provisioner/helperPod.yaml")
  }
}

resource "kubernetes_deployment_v1" "local_path_provisioner" {
  metadata {
    name      = "local-path-provisioner"
    namespace = kubernetes_namespace_v1.local_path_storage.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "local-path-provisioner"
      }
    }

    template {
      metadata {
        labels = {
          app = "local-path-provisioner"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.local_path_provisioner.metadata[0].name

        container {
          name              = "local-path-provisioner"
          image             = "docker.io/rancher/local-path-provisioner:v0.0.36"
          image_pull_policy = "IfNotPresent"
          command           = ["local-path-provisioner", "--debug", "start", "--config", "/etc/config/config.json"]

          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/config/"
          }

          env {
            name = "POD_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          env {
            name  = "CONFIG_MOUNT_PATH"
            value = "/etc/config/"
          }
        }

        volume {
          name = "config-volume"
          config_map {
            name = kubernetes_config_map_v1.local_path_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_storage_class_v1" "local_path" {
  metadata {
    name = "local-path"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner = "rancher.io/local-path"
  volume_binding_mode = "WaitForFirstConsumer"
  reclaim_policy      = "Delete"
}
