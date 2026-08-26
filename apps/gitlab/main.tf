resource "kubernetes_namespace_v1" "forge" {
  metadata {
    name = "forge"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "cloudflare_dns_record" "gitlab_vinnel_cloud" {
  zone_id = var.zone_id
  name    = "gitlab.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "artifacts_vinnel_cloud" {
  zone_id = var.zone_id
  name    = "artifacts.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = false
}

resource "random_password" "gitlab_root_password" {
  length  = 32
  special = false
}

locals {
  gitlab_omnibus_config = join("\n", [
    "external_url 'https://gitlab.vinnel.cloud'",
    "registry_external_url 'https://artifacts.vinnel.cloud'",
    "registry['enable'] = true",
    "registry['storage'] = { 's3' => { 'accesskey' => '${var.seaweedfs_s3_access_key}', 'secretkey' => '${var.seaweedfs_s3_secret_key}', 'bucket' => 'gitlab-registry', 'region' => 'us-east-1', 'regionendpoint' => 'http://seaweedfs.storage.svc.cluster.local:8333', 'secure' => false, 'v4auth' => true, 'forcepathstyle' => true }, 'redirect' => { 'disable' => true } }",
    "registry_nginx['enable'] = true",
    "registry_nginx['listen_https'] = false",
    "registry_nginx['listen_port'] = 5050",
    "registry_nginx['proxy_set_headers'] = { 'X-Forwarded-Proto' => 'https', 'X-Forwarded-Ssl' => 'on' }",
    "gitlab_rails['dependency_proxy_enabled'] = true",
    "gitlab_rails['gitlab_shell_ssh_port'] = 2222",
    "gitlab_rails['smtp_enable'] = true",
    "gitlab_rails['smtp_address'] = 'smtp.resend.com'",
    "gitlab_rails['smtp_port'] = 587",
    "gitlab_rails['smtp_user_name'] = 'resend'",
    "gitlab_rails['smtp_password'] = ENV['GITLAB_SMTP_PASSWORD']",
    "gitlab_rails['smtp_domain'] = 'vinnel.cloud'",
    "gitlab_rails['smtp_authentication'] = 'login'",
    "gitlab_rails['smtp_enable_starttls_auto'] = true",
    "gitlab_rails['smtp_tls'] = false",
    "gitlab_rails['gitlab_email_from'] = 'alerts@vinnel.cloud'",
    "gitlab_rails['gitlab_email_reply_to'] = 'alerts@vinnel.cloud'",
    "letsencrypt['enable'] = false",
    "nginx['listen_port'] = 80",
    "nginx['listen_https'] = false",
    "nginx['proxy_set_headers'] = { 'X-Forwarded-Proto' => 'https', 'X-Forwarded-Ssl' => 'on' }",
    "gitlab_rails['monitoring_whitelist'] = ['127.0.0.0/8', '10.244.0.0/16']",
    "puma['worker_processes'] = 4",
    "puma['per_worker_max_memory_mb'] = 1400",
    "sidekiq['max_concurrency'] = 10",
    "postgresql['shared_buffers'] = '2GB'",
    "postgresql['effective_cache_size'] = '6GB'",
  ])

  gitlab_config_hash = sha256(join("", [
    random_password.gitlab_root_password.result,
    var.resend_api_key,
    local.gitlab_omnibus_config,
  ]))
}

resource "kubernetes_secret_v1" "gitlab_credentials" {
  metadata {
    name      = "gitlab-credentials"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
  }
  data = {
    root-password = random_password.gitlab_root_password.result
    smtp-password = var.resend_api_key
  }
}

resource "kubernetes_persistent_volume_claim_v1" "gitlab_config" {
  metadata {
    name      = "gitlab-config-pvc"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
    annotations = {
      "volumeType" = "hostPath"
    }
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_persistent_volume_claim_v1" "gitlab_logs" {
  metadata {
    name      = "gitlab-logs-pvc"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
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

resource "kubernetes_persistent_volume_claim_v1" "gitlab_data" {
  metadata {
    name      = "gitlab-data-pvc"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
    annotations = {
      "volumeType" = "hostPath"
    }
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "100Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_deployment_v1" "gitlab" {
  metadata {
    name      = "gitlab"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
    labels = {
      app = "gitlab"
    }
  }

  spec {
    replicas                  = 1
    progress_deadline_seconds = 1200

    selector {
      match_labels = {
        app = "gitlab"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "gitlab"
        }
        annotations = {
          "config-hash" = local.gitlab_config_hash
        }
      }

      spec {
        enable_service_links = false

        container {
          name  = "gitlab"
          image = "gitlab/gitlab-ce:19.3.1-ce.0@sha256:f63df4c43029fe91db370609c0b40a1e3585cebd06e3e9637d93a9a3030eb86e"

          env {
            name  = "GITLAB_OMNIBUS_CONFIG"
            value = local.gitlab_omnibus_config
          }
          env {
            name  = "GITLAB_ROOT_EMAIL"
            value = var.acme_email_vin_moe
          }
          env {
            name = "GITLAB_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.gitlab_credentials.metadata[0].name
                key  = "root-password"
              }
            }
          }
          env {
            name = "GITLAB_SMTP_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.gitlab_credentials.metadata[0].name
                key  = "smtp-password"
              }
            }
          }

          port {
            name           = "http"
            container_port = 80
          }
          port {
            name           = "registry"
            container_port = 5050
          }

          resources {
            requests = {
              cpu    = "2000m"
              memory = "8Gi"
            }
            limits = {
              cpu    = "4000m"
              memory = "20Gi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/gitlab"
          }
          volume_mount {
            name       = "logs"
            mount_path = "/var/log/gitlab"
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/opt/gitlab"
          }
          volume_mount {
            name       = "dshm"
            mount_path = "/dev/shm"
          }

          startup_probe {
            http_get {
              path = "/-/health"
              port = "http"
            }
            period_seconds        = 15
            failure_threshold     = 80
            initial_delay_seconds = 30
          }

          readiness_probe {
            http_get {
              path = "/-/readiness"
              port = "http"
            }
            period_seconds  = 10
            timeout_seconds = 5
          }

          liveness_probe {
            http_get {
              path = "/-/liveness"
              port = "http"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        volume {
          name = "config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.gitlab_config.metadata[0].name
          }
        }
        volume {
          name = "logs"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.gitlab_logs.metadata[0].name
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.gitlab_data.metadata[0].name
          }
        }
        volume {
          name = "dshm"
          empty_dir {
            medium     = "Memory"
            size_limit = "512Mi"
          }
        }
      }
    }
  }

  timeouts {
    create = "20m"
    update = "20m"
  }
}

module "gitlab_vpa" {
  source = "../../platform/vpa/resource"

  depends_on = [kubernetes_deployment_v1.gitlab]

  name        = "gitlab"
  namespace   = kubernetes_namespace_v1.forge.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.gitlab.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "gitlab", min_memory = "4Gi", max_memory = "20Gi" },
  ]
}

resource "kubernetes_service_v1" "gitlab" {
  metadata {
    name      = "gitlab"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "gitlab"
    }
    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }
    port {
      name        = "registry"
      port        = 5050
      target_port = "registry"
    }
  }
}

resource "kubernetes_ingress_v1" "gitlab_vinnel_cloud" {
  depends_on = [kubernetes_deployment_v1.gitlab]
  metadata {
    name      = "gitlab-vinnel-cloud"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"                 = var.cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-body-size"    = "0"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "300"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = ["gitlab.vinnel.cloud"]
      secret_name = "gitlab-vinnel-cloud-tls"
    }

    rule {
      host = "gitlab.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.gitlab.metadata[0].name
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

# --- Phase B: GitLab Runner, Kubernetes executor ---

resource "kubernetes_ingress_v1" "artifacts_vinnel_cloud" {
  depends_on = [kubernetes_deployment_v1.gitlab]
  metadata {
    name      = "artifacts-vinnel-cloud"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"              = var.cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-body-size" = "0"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = ["artifacts.vinnel.cloud"]
      secret_name = "artifacts-vinnel-cloud-tls"
    }

    rule {
      host = "artifacts.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.gitlab.metadata[0].name
              port {
                number = 5050
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_account_v1" "gitlab_runner" {
  metadata {
    name      = "gitlab-runner"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
  }
}

resource "kubernetes_role_v1" "gitlab_runner" {
  metadata {
    name      = "gitlab-runner"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["create", "delete", "get", "list", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/attach"]
    verbs      = ["create", "delete", "get", "patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["create", "delete", "get", "patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["create", "delete", "get", "update"]
  }
  rule {
    api_groups = [""]
    resources  = ["services"]
    verbs      = ["create", "get"]
  }
  rule {
    api_groups = [""]
    resources  = ["serviceaccounts"]
    verbs      = ["get"]
  }
}

resource "kubernetes_role_binding_v1" "gitlab_runner" {
  metadata {
    name      = "gitlab-runner"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.gitlab_runner.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.gitlab_runner.metadata[0].name
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
  }
}

resource "gitlab_project_deploy_token" "registry" {
  project = gitlab_project.gaia.id
  name    = "registry-pull"
  scopes  = ["read_registry"]
}

resource "kubernetes_secret_v1" "registry_dockerconfig_gitlab" {
  metadata {
    name      = "registry-dockerconfig"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "artifacts.vinnel.cloud" = {
          username = gitlab_project_deploy_token.registry.username
          password = gitlab_project_deploy_token.registry.token
          auth     = base64encode("${gitlab_project_deploy_token.registry.username}:${gitlab_project_deploy_token.registry.token}")
        }
      }
    })
  }
}

locals {
  registry_dockerconfigjson = jsonencode({
    auths = {
      "artifacts.vinnel.cloud" = {
        username = gitlab_project_deploy_token.registry.username
        password = gitlab_project_deploy_token.registry.token
        auth     = base64encode("${gitlab_project_deploy_token.registry.username}:${gitlab_project_deploy_token.registry.token}")
      }
    }
  })
}

resource "gitlab_group_dependency_proxy" "vinnel_cloud" {
  group    = gitlab_group.vinnel_cloud.id
  enabled  = true
  identity = var.docker_hub_username
  secret   = var.docker_hub_access_token
}

resource "gitlab_user_runner" "gaia" {
  runner_type = "instance_type"
  description = "gaia in-cluster Kubernetes executor (apps-gitlab.tf)"
  tag_list    = ["kubernetes", "gaia"]
  untagged    = true
}

locals {
  gitlab_runner_config_toml = <<-EOT
    concurrent     = 4
    check_interval = 3

    [[runners]]
      name     = "gaia-k8s"
      url      = "https://gitlab.vinnel.cloud"
      token    = "${gitlab_user_runner.gaia.token}"
      executor = "kubernetes"

      [runners.kubernetes]
        namespace          = "${kubernetes_namespace_v1.forge.metadata[0].name}"
        service_account    = "${kubernetes_service_account_v1.gitlab_runner.metadata[0].name}"
        image              = "alpine:3.24"
        image_pull_secrets = ["${kubernetes_secret_v1.registry_dockerconfig_gitlab.metadata[0].name}"]
        host_aliases       = [{ ip = "${var.node_ip}", hostnames = ["registry.vinnel.cloud"] }]
  EOT

  gitlab_runner_config_hash = sha256(local.gitlab_runner_config_toml)
}

resource "kubernetes_secret_v1" "gitlab_runner_config" {
  metadata {
    name      = "gitlab-runner-config"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
  }
  data = {
    "config.toml" = local.gitlab_runner_config_toml
  }
}

resource "kubernetes_deployment_v1" "gitlab_runner" {
  metadata {
    name      = "gitlab-runner"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
    labels = {
      app = "gitlab-runner"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "gitlab-runner"
      }
    }

    template {
      metadata {
        labels = {
          app = "gitlab-runner"
        }
        annotations = {
          "config-hash" = local.gitlab_runner_config_hash
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.gitlab_runner.metadata[0].name

        container {
          name  = "gitlab-runner"
          image = "gitlab/gitlab-runner:v19.3.1@sha256:74209bd51542dc0cb8aa584f103b34c857ff240c3a275559af307c1cb1efbe4f"

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/gitlab-runner/config.toml"
            sub_path   = "config.toml"
          }
        }

        volume {
          name = "config"
          secret {
            secret_name = kubernetes_secret_v1.gitlab_runner_config.metadata[0].name
          }
        }
      }
    }
  }
}

module "gitlab_runner_vpa" {
  source = "../../platform/vpa/resource"

  depends_on = [kubernetes_deployment_v1.gitlab_runner]

  name        = "gitlab-runner"
  namespace   = kubernetes_namespace_v1.forge.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.gitlab_runner.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "gitlab-runner", min_memory = "64Mi", max_memory = "512Mi" },
  ]
}

# --- Second runner: privileged, image builds only ---

resource "gitlab_user_runner" "gaia_privileged_build" {
  runner_type = "instance_type"
  description = "gaia in-cluster Kubernetes executor - privileged, image builds only (apps-gitlab.tf)"
  tag_list    = ["kubernetes", "privileged-build"]
  untagged    = false
}

locals {
  gitlab_runner_privileged_config_toml = <<-EOT
    concurrent     = 2
    check_interval = 3

    [[runners]]
      name     = "gaia-k8s-privileged-build"
      url      = "https://gitlab.vinnel.cloud"
      token    = "${gitlab_user_runner.gaia_privileged_build.token}"
      executor = "kubernetes"

      [runners.kubernetes]
        namespace          = "${kubernetes_namespace_v1.forge.metadata[0].name}"
        service_account    = "${kubernetes_service_account_v1.gitlab_runner.metadata[0].name}"
        image              = "alpine:3.24"
        image_pull_secrets = ["${kubernetes_secret_v1.registry_dockerconfig_gitlab.metadata[0].name}"]
        host_aliases       = [{ ip = "${var.node_ip}", hostnames = ["registry.vinnel.cloud"] }]
        privileged         = true
  EOT

  gitlab_runner_privileged_config_hash = sha256(local.gitlab_runner_privileged_config_toml)
}

resource "kubernetes_secret_v1" "gitlab_runner_privileged_config" {
  metadata {
    name      = "gitlab-runner-privileged-config"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
  }
  data = {
    "config.toml" = local.gitlab_runner_privileged_config_toml
  }
}

resource "kubernetes_deployment_v1" "gitlab_runner_privileged" {
  metadata {
    name      = "gitlab-runner-privileged-build"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
    labels = {
      app = "gitlab-runner-privileged-build"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "gitlab-runner-privileged-build"
      }
    }

    template {
      metadata {
        labels = {
          app = "gitlab-runner-privileged-build"
        }
        annotations = {
          "config-hash" = local.gitlab_runner_privileged_config_hash
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.gitlab_runner.metadata[0].name

        container {
          name  = "gitlab-runner"
          image = "gitlab/gitlab-runner:v19.3.1@sha256:74209bd51542dc0cb8aa584f103b34c857ff240c3a275559af307c1cb1efbe4f"

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/gitlab-runner/config.toml"
            sub_path   = "config.toml"
          }
        }

        volume {
          name = "config"
          secret {
            secret_name = kubernetes_secret_v1.gitlab_runner_privileged_config.metadata[0].name
          }
        }
      }
    }
  }
}

module "gitlab_runner_privileged_vpa" {
  source = "../../platform/vpa/resource"

  depends_on = [kubernetes_deployment_v1.gitlab_runner_privileged]

  name        = "gitlab-runner-privileged-build"
  namespace   = kubernetes_namespace_v1.forge.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.gitlab_runner_privileged.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "gitlab-runner", min_memory = "64Mi", max_memory = "512Mi" },
  ]
}

# --- Phase C: git migration + outbound mirrors ---

resource "gitlab_group" "vinnel_cloud" {
  name             = "vinnel.cloud"
  path             = "vinnel-cloud"
  description      = "vinnel.cloud homelab projects"
  visibility_level = "private"
}

resource "gitlab_project" "gaia" {
  name                                     = "gaia"
  path                                     = "gaia"
  namespace_id                             = gitlab_group.vinnel_cloud.id
  description                              = "Talos/k8s homelab IaC -- canonical source, migrated from GitHub"
  visibility_level                         = "private"
  initialize_with_readme                   = false
  default_branch                           = "prd"
  ci_push_repository_for_job_token_allowed = true

  only_allow_merge_if_pipeline_succeeds            = true
  allow_merge_on_skipped_pipeline                  = false
  merge_method                                     = "merge"
  remove_source_branch_after_merge                 = true
  only_allow_merge_if_all_discussions_are_resolved = false
}

resource "gitlab_branch" "pre" {
  project = gitlab_project.gaia.id
  name    = "pre"
  ref     = gitlab_project.gaia.default_branch
}

resource "gitlab_branch_protection" "prd" {
  project            = gitlab_project.gaia.id
  branch             = gitlab_project.gaia.default_branch
  push_access_level  = "maintainer"
  merge_access_level = "maintainer"
  allow_force_push   = false
}

resource "gitlab_project_access_token" "ci_bot" {
  project      = gitlab_project.gaia.id
  name         = "gaia-ci-bot"
  scopes       = ["api", "write_repository"]
  access_level = "maintainer"
  expires_at   = "2027-08-01"
}

resource "gitlab_project_variable" "ci_bot_token" {
  project   = gitlab_project.gaia.id
  key       = "CI_BOT_TOKEN"
  value     = gitlab_project_access_token.ci_bot.token
  masked    = true
  protected = false
}

resource "gitlab_project_variable" "gh_api_token" {
  project   = gitlab_project.gaia.id
  key       = "GH_API_TOKEN"
  value     = var.gitlab_mirror_github_pat
  masked    = true
  protected = false
}

resource "gitlab_project_variable" "tfc_api_token" {
  project   = gitlab_project.gaia.id
  key       = "TF_TOKEN_app_terraform_io"
  value     = var.gitlab_tfc_api_token
  masked    = true
  protected = false
}

resource "gitlab_pipeline_trigger" "reconcile" {
  project     = gitlab_project.gaia.id
  description = "generic: re-trigger a pipeline after a bot commit (image digest record, ci-runner rebuild, etc.) that job-token pushes might not fire automatically"
}

resource "gitlab_project_variable" "reconcile_trigger_token" {
  project   = gitlab_project.gaia.id
  key       = "RECONCILE_TRIGGER_TOKEN"
  value     = gitlab_pipeline_trigger.reconcile.token
  masked    = true
  protected = false
}

resource "gitlab_pipeline_schedule" "ci_runner_scan" {
  project       = gitlab_project.gaia.id
  description   = "Nightly ci-runner image vulnerability scan"
  ref           = "refs/heads/prd"
  cron          = "0 6 * * *"
  cron_timezone = "UTC"
  active        = true
}

resource "gitlab_project_variable" "site_deploy_kubeconfig" {
  project       = gitlab_project.gaia.id
  key           = "SITE_DEPLOY_KUBECONFIG"
  value         = var.ci_kubeconfig
  variable_type = "file"
  masked        = false
  protected     = false
}

resource "gitlab_project_variable" "cf_api_token" {
  project   = gitlab_project.gaia.id
  key       = "CF_API_TOKEN"
  value     = var.cloudflare_cache_purge_token
  masked    = true
  protected = false
}
