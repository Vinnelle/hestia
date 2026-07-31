
resource "cloudflare_dns_record" "kc_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "kc.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "random_password" "keycloak_admin_password" {
  length  = 32
  special = false
}

resource "random_password" "keycloak_oidc_client_secret" {
  length  = 48
  special = false
}

resource "kubernetes_persistent_volume_claim_v1" "keycloak" {
  metadata {
    name      = "keycloak-pvc"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "2Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_secret_v1" "keycloak_admin" {
  metadata {
    name      = "keycloak-admin"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
  }
  data = {
    password = random_password.keycloak_admin_password.result
  }
}

resource "kubernetes_deployment_v1" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
    labels = {
      app = "keycloak"
    }
  }

  spec {

    replicas = 1

    selector {
      match_labels = {
        app = "keycloak"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "keycloak"
        }
        annotations = {

          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9000"
        }
      }

      spec {
        enable_service_links = false

        security_context {

          fs_group = 1000
        }

        container {
          name  = "keycloak"
          image = "quay.io/keycloak/keycloak:26.7"

          args = [
            "start",
            "--db", "dev-file",
            "--http-enabled", "true",
            "--proxy-headers", "xforwarded",
            "--hostname", "https://kc.vinnel.cloud",
            "--health-enabled", "true",
            "--metrics-enabled", "true",
          ]

          env {
            name  = "KC_BOOTSTRAP_ADMIN_USERNAME"
            value = "admin"
          }

          env {
            name = "KC_BOOTSTRAP_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.keycloak_admin.metadata[0].name
                key  = "password"
              }
            }
          }

          port {
            name           = "http"
            container_port = 8080
          }

          port {
            name           = "management"
            container_port = 9000
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1"
              memory = "1Gi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/opt/keycloak/data"
          }

          startup_probe {
            http_get {
              path = "/health/started"
              port = "management"
            }
            period_seconds    = 5
            failure_threshold = 60
            timeout_seconds   = 3
          }

          readiness_probe {
            http_get {
              path = "/health/ready"
              port = "management"
            }
            period_seconds  = 10
            timeout_seconds = 5
          }

          liveness_probe {
            http_get {
              path = "/health/live"
              port = "management"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.keycloak.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubectl_manifest" "keycloak_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.keycloak]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "keycloak"
    namespace   = kubernetes_namespace_v1.services.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.keycloak.metadata[0].name
    update_mode = "Initial"
    container_policies = [
      { container_name = "keycloak", min_memory = "512Mi", max_memory = "1Gi" },
    ]
  })
}

resource "kubernetes_service_v1" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "keycloak"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_ingress_v1" "keycloak" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer

      "nginx.ingress.kubernetes.io/proxy-buffer-size" = "128k"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["kc.vinnel.cloud"]
      secret_name = "keycloak-tls"
    }

    rule {
      host = "kc.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.keycloak.metadata[0].name
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

resource "keycloak_realm" "vinnel" {
  depends_on = [
    kubernetes_deployment_v1.keycloak,
    kubernetes_ingress_v1.keycloak,
    cloudflare_dns_record.kc_vinnel_cloud,
  ]

  realm        = "vinnel"
  display_name = "vinnel.cloud"

  security_defenses {
    headers {
      x_frame_options                     = "DENY"
      content_security_policy             = "frame-src 'self'; frame-ancestors 'self' https://admin.vinnel.cloud; object-src 'none';"
      content_security_policy_report_only = ""
      x_content_type_options              = "nosniff"
      x_robots_tag                        = "none"
      x_xss_protection                    = "1; mode=block"
      strict_transport_security           = "max-age=31536000; includeSubDomains"
    }
  }
}

resource "keycloak_oidc_identity_provider" "authelia" {
  realm              = keycloak_realm.vinnel.id
  alias              = "authelia"
  display_name       = "Authelia"
  authorization_url  = "https://auth.vinnel.cloud/api/oidc/authorization"
  token_url          = "https://auth.vinnel.cloud/api/oidc/token"
  user_info_url      = "https://auth.vinnel.cloud/api/oidc/userinfo"
  jwks_url           = "https://auth.vinnel.cloud/jwks.json"
  issuer             = "https://auth.vinnel.cloud"
  validate_signature = true
  client_id          = "keycloak"
  client_secret      = random_password.keycloak_oidc_client_secret.result
  default_scopes     = "openid email profile"
  trust_email        = true
  sync_mode          = "IMPORT"

  extra_config = {

    clientAuthMethod = "client_secret_post"
  }
}

resource "keycloak_authentication_flow" "browser_authelia" {
  realm_id = keycloak_realm.vinnel.id
  alias    = "browser-authelia"
}

resource "keycloak_authentication_execution" "browser_cookie" {
  realm_id          = keycloak_realm.vinnel.id
  parent_flow_alias = keycloak_authentication_flow.browser_authelia.alias
  authenticator     = "auth-cookie"
  requirement       = "ALTERNATIVE"
  priority          = 10
}

resource "keycloak_authentication_execution" "browser_idp_redirect" {
  realm_id          = keycloak_realm.vinnel.id
  parent_flow_alias = keycloak_authentication_flow.browser_authelia.alias
  authenticator     = "identity-provider-redirector"
  requirement       = "ALTERNATIVE"
  priority          = 20
}

resource "keycloak_authentication_execution_config" "browser_idp_redirect" {
  realm_id     = keycloak_realm.vinnel.id
  execution_id = keycloak_authentication_execution.browser_idp_redirect.id
  alias        = "authelia-redirect"
  config = {
    defaultProvider = keycloak_oidc_identity_provider.authelia.alias
  }
}

resource "keycloak_authentication_bindings" "vinnel" {
  realm_id     = keycloak_realm.vinnel.id
  browser_flow = keycloak_authentication_flow.browser_authelia.alias
}

resource "tls_private_key" "ceph_dashboard_sp" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ceph_dashboard_sp" {
  private_key_pem = tls_private_key.ceph_dashboard_sp.private_key_pem

  subject {
    common_name = "ceph.vinnel.cloud"
  }

  validity_period_hours = 87600
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
  ]
}

resource "keycloak_saml_client" "ceph_dashboard" {
  realm_id  = keycloak_realm.vinnel.id
  client_id = "https://ceph.vinnel.cloud/auth/saml2/metadata"
  name      = "Ceph Dashboard"

  sign_documents            = true
  sign_assertions           = true
  client_signature_required = false
  front_channel_logout      = true
  force_post_binding        = true

  encrypt_assertions     = true
  encryption_certificate = tls_self_signed_cert.ceph_dashboard_sp.cert_pem

  valid_redirect_uris         = ["https://ceph.vinnel.cloud/auth/saml2"]
  assertion_consumer_post_url = "https://ceph.vinnel.cloud/auth/saml2"
  name_id_format              = "username"
}

resource "keycloak_saml_user_property_protocol_mapper" "ceph_uid" {
  realm_id                   = keycloak_realm.vinnel.id
  client_id                  = keycloak_saml_client.ceph_dashboard.id
  name                       = "uid"
  user_property              = "username"
  saml_attribute_name        = "uid"
  saml_attribute_name_format = "Basic"
}

resource "kubernetes_service_account_v1" "ceph_dashboard_sso_setup" {
  metadata {
    name      = "ceph-dashboard-sso-setup"
    namespace = kubernetes_namespace_v1.rook_ceph.metadata[0].name
  }
}

resource "kubernetes_role_v1" "ceph_dashboard_sso_setup" {
  metadata {
    name      = "ceph-dashboard-sso-setup"
    namespace = kubernetes_namespace_v1.rook_ceph.metadata[0].name
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["create"]
  }
}

resource "kubernetes_role_binding_v1" "ceph_dashboard_sso_setup" {
  metadata {
    name      = "ceph-dashboard-sso-setup"
    namespace = kubernetes_namespace_v1.rook_ceph.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.ceph_dashboard_sso_setup.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.ceph_dashboard_sso_setup.metadata[0].name
    namespace = kubernetes_namespace_v1.rook_ceph.metadata[0].name
  }
}

locals {
  ceph_dashboard_sso_script = <<-EOT
    set -e
    kubectl -n rook-ceph exec -i deploy/rook-ceph-mgr-a -c mgr -- sh -c 'cat > /tmp/sp-cert.pem && chmod 644 /tmp/sp-cert.pem' <<'CERT'
    ${tls_self_signed_cert.ceph_dashboard_sp.cert_pem}
    CERT
    kubectl -n rook-ceph exec -i deploy/rook-ceph-mgr-a -c mgr -- sh -c 'cat > /tmp/sp-key.pem && chmod 644 /tmp/sp-key.pem' <<'KEY'
    ${tls_private_key.ceph_dashboard_sp.private_key_pem}
    KEY
    kubectl -n rook-ceph exec -i deploy/rook-ceph-tools -- sh -c 'head -c 32 /dev/urandom | base64 | ceph dashboard ac-user-create ida administrator --enabled -i -' || true
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- sh -c '
      curl -sS https://kc.vinnel.cloud/realms/vinnel/protocol/saml/descriptor -o /tmp/idp-metadata.xml
      ceph dashboard sso setup saml2 https://ceph.vinnel.cloud "$(cat /tmp/idp-metadata.xml)" uid https://kc.vinnel.cloud/realms/vinnel /tmp/sp-cert.pem /tmp/sp-key.pem
    '
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph mgr module disable dashboard
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph mgr module enable dashboard
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph dashboard sso status
  EOT

  ceph_dashboard_sso_setup_image = "alpine/k8s:1.31.13"
}

resource "kubernetes_job_v1" "ceph_dashboard_sso_setup" {
  depends_on = [
    helm_release.rook_ceph_cluster,
    keycloak_saml_client.ceph_dashboard,
    keycloak_saml_user_property_protocol_mapper.ceph_uid,
    kubernetes_role_binding_v1.ceph_dashboard_sso_setup,
  ]

  metadata {
    name      = "ceph-dashboard-sso-setup-${substr(sha256("${local.ceph_dashboard_sso_script}${local.ceph_dashboard_sso_setup_image}"), 0, 8)}"
    namespace = kubernetes_namespace_v1.rook_ceph.metadata[0].name
  }

  spec {
    backoff_limit = 2

    template {
      metadata {
        labels = {
          app = "ceph-dashboard-sso-setup"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.ceph_dashboard_sso_setup.metadata[0].name
        restart_policy       = "OnFailure"

        container {
          name    = "setup"
          image   = local.ceph_dashboard_sso_setup_image
          command = ["sh", "-c", local.ceph_dashboard_sso_script]
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "5m"
  }
}
