# Keycloak — SAML<->OIDC bridge for the Ceph dashboard, nothing more. Ceph's
# dashboard can only do SSO via SAML2 on a Rook cluster (its OAuth2 path needs
# cephadm's mgmt-gateway/oauth2-proxy, which Rook doesn't run), and Authelia has
# no SAML IdP support. Keycloak fronts Ceph as a SAML IdP and brokers the actual
# authentication upstream to Authelia over OIDC, so login stays Authelia and this
# realm carries no passwords of its own. See CLAUDE.md for the full rationale and
# the one-time Ceph-side toolbox runbook.

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

# Plaintext goes to Keycloak's broker config below; the Authelia side gets the
# bcrypt hash (identity-authelia.tf) — same split as netbird-dashboard's secret.
resource "random_password" "keycloak_oidc_client_secret" {
  length  = 48
  special = false
}

# ponytail: dev-file H2 on a PVC, no postgres. The entire DB is disposable —
# realm config is Terraform-managed and the only user is broker-created on next
# login — so a real DB buys nothing here. Upgrade to postgres if Keycloak ever
# serves more than this one bridge realm.
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
    # Single replica, Recreate: RWO PVC, and the H2 file store allows exactly
    # one writer anyway.
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
          # Management port serves /metrics — cluster-wide scrape convention,
          # see observability-signoz.tf notes in CLAUDE.md.
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9000"
        }
      }

      spec {
        enable_service_links = false

        security_context {
          # The upstream image runs as UID 1000; fs_group hands it the PVC.
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

          # JVM start is slow — startup probe carries the boot, then the usual
          # readiness/liveness take over on the management port.
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

# No Authelia forward-auth: this IS an IdP hop — the browser only ever lands
# here mid-flight between Ceph and Authelia, and forward-auth would break the
# SAML POST callbacks. Same reasoning as Authelia's own ingress.
resource "kubernetes_ingress_v1" "keycloak" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer
      # Keycloak's responses carry big headers (admin console cookies, SAML
      # payloads); ingress-nginx's default 4k proxy buffer 502s on them.
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

# ---------------------------------------------------------------------------
# Realm configuration. Same lazy-provider bootstrap as harbor_project: these
# resources reach https://kc.vinnel.cloud, so on a cold apply they must wait
# for the deployment, ingress and DNS record above. Cert issuance can still
# race a first apply — a re-apply converges.
# ---------------------------------------------------------------------------

resource "keycloak_realm" "vinnel" {
  depends_on = [
    kubernetes_deployment_v1.keycloak,
    kubernetes_ingress_v1.keycloak,
    cloudflare_dns_record.kc_vinnel_cloud,
  ]

  realm        = "vinnel"
  display_name = "vinnel.cloud"
}

# Authelia as the upstream authentication source: Keycloak never shows its own
# login form (browser flow below redirects straight out), it just mints SAML
# assertions from the brokered Authelia identity.
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
    # Must match the Authelia client's token_endpoint_auth_method.
    clientAuthMethod = "client_secret_post"
  }
}

# Browser flow = cookie, else bounce straight to Authelia. This is what makes
# the bridge invisible: no Keycloak login page, no IdP picker.
resource "keycloak_authentication_flow" "browser_authelia" {
  realm_id = keycloak_realm.vinnel.id
  alias    = "browser-authelia"
}

# Explicit priorities (KC >= 25) instead of the old creation-order/depends_on
# dance — lower value sits higher in the flow.
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

# The Ceph dashboard as SAML SP. client_id must equal the SP entity ID Ceph
# derives from its base URL (<base>/auth/saml2/metadata); the ACS lives at
# <base>/auth/saml2. Ceph is set up without an SP cert/key (the optional args
# to `ceph dashboard sso setup saml2`), so it can't sign AuthnRequests —
# client_signature_required must stay false or every login 400s.
resource "keycloak_saml_client" "ceph_dashboard" {
  realm_id  = keycloak_realm.vinnel.id
  client_id = "https://ceph.vinnel.cloud/auth/saml2/metadata"
  name      = "Ceph Dashboard"

  sign_documents            = true
  sign_assertions           = true
  client_signature_required = false
  front_channel_logout      = true
  force_post_binding        = true

  valid_redirect_uris         = ["https://ceph.vinnel.cloud/auth/saml2"]
  assertion_consumer_post_url = "https://ceph.vinnel.cloud/auth/saml2"
  name_id_format              = "username"
}

# Ceph reads the username from a SAML attribute (`uid` is what the runbook
# passes to `sso setup saml2`), not the NameID — emit it explicitly so the
# mapping is deterministic.
resource "keycloak_saml_user_property_protocol_mapper" "ceph_uid" {
  realm_id                   = keycloak_realm.vinnel.id
  client_id                  = keycloak_saml_client.ceph_dashboard.id
  name                       = "uid"
  user_property              = "username"
  saml_attribute_name        = "uid"
  saml_attribute_name_format = "Basic"
}
