moved {
  from = kubernetes_namespace_v1.searxng
  to   = module.searxng.kubernetes_namespace_v1.searxng
}

moved {
  from = cloudflare_dns_record.search_vinnel_cloud
  to   = module.searxng.cloudflare_dns_record.search_vinnel_cloud
}

moved {
  from = random_password.searxng_secret
  to   = module.searxng.random_password.searxng_secret
}

moved {
  from = kubernetes_secret_v1.searxng
  to   = module.searxng.kubernetes_secret_v1.searxng
}

moved {
  from = kubernetes_deployment_v1.searxng
  to   = module.searxng.kubernetes_deployment_v1.searxng
}

moved {
  from = module.searxng_vpa
  to   = module.searxng.module.vpa
}

moved {
  from = kubernetes_service_v1.searxng
  to   = module.searxng.kubernetes_service_v1.searxng
}

moved {
  from = kubernetes_ingress_v1.search_vinnel_cloud
  to   = module.searxng.kubernetes_ingress_v1.search_vinnel_cloud
}
moved {
  from = kubernetes_namespace_v1.platform
  to   = module.platform_core.kubernetes_namespace_v1.platform
}

moved {
  from = helm_release.ingress_nginx
  to   = module.platform_core.helm_release.ingress_nginx
}

moved {
  from = helm_release.cert_manager
  to   = module.platform_core.helm_release.cert_manager
}

moved {
  from = cloudflare_zone_setting.vin_moe_ssl
  to   = module.platform_core.cloudflare_zone_setting.vin_moe_ssl
}

moved {
  from = cloudflare_zone_setting.vinnel_cloud_ssl
  to   = module.platform_core.cloudflare_zone_setting.vinnel_cloud_ssl
}

moved {
  from = cloudflare_zone_setting.monke_academy_ssl
  to   = module.platform_core.cloudflare_zone_setting.monke_academy_ssl
}

moved {
  from = kubernetes_secret_v1.cloudflare_api_token
  to   = module.platform_core.kubernetes_secret_v1.cloudflare_api_token
}

moved {
  from = helm_release.metrics_server
  to   = module.platform_vpa.helm_release.metrics_server
}

moved {
  from = helm_release.vpa
  to   = module.platform_vpa.helm_release.vpa
}

moved {
  from = kubernetes_namespace_v1.storage
  to   = module.platform_storage.kubernetes_namespace_v1.storage
}

moved {
  from = kubernetes_service_account_v1.local_path_provisioner
  to   = module.platform_storage.kubernetes_service_account_v1.local_path_provisioner
}

moved {
  from = kubernetes_role_v1.local_path_provisioner
  to   = module.platform_storage.kubernetes_role_v1.local_path_provisioner
}

moved {
  from = kubernetes_cluster_role_v1.local_path_provisioner
  to   = module.platform_storage.kubernetes_cluster_role_v1.local_path_provisioner
}

moved {
  from = kubernetes_role_binding_v1.local_path_provisioner
  to   = module.platform_storage.kubernetes_role_binding_v1.local_path_provisioner
}

moved {
  from = kubernetes_cluster_role_binding_v1.local_path_provisioner
  to   = module.platform_storage.kubernetes_cluster_role_binding_v1.local_path_provisioner
}

moved {
  from = kubernetes_config_map_v1.local_path_config
  to   = module.platform_storage.kubernetes_config_map_v1.local_path_config
}

moved {
  from = kubernetes_deployment_v1.local_path_provisioner
  to   = module.platform_storage.kubernetes_deployment_v1.local_path_provisioner
}

moved {
  from = kubernetes_storage_class_v1.local_path
  to   = module.platform_storage.kubernetes_storage_class_v1.local_path
}

moved {
  from = kubernetes_storage_class_v1.local_path_hostpath
  to   = module.platform_storage.kubernetes_storage_class_v1.local_path_hostpath
}

moved {
  from = kubernetes_storage_class_v1.local_path_bulk
  to   = module.platform_storage.kubernetes_storage_class_v1.local_path_bulk
}

moved {
  from = cloudflare_dns_record.s3_vinnel_cloud
  to   = module.seaweedfs.cloudflare_dns_record.s3_vinnel_cloud
}

moved {
  from = cloudflare_dns_record.seaweed_vinnel_cloud
  to   = module.seaweedfs.cloudflare_dns_record.seaweed_vinnel_cloud
}

moved {
  from = random_password.seaweedfs_s3_access_key
  to   = module.seaweedfs.random_password.seaweedfs_s3_access_key
}

moved {
  from = random_password.seaweedfs_s3_secret_key
  to   = module.seaweedfs.random_password.seaweedfs_s3_secret_key
}

moved {
  from = kubernetes_secret_v1.seaweedfs_s3_config
  to   = module.seaweedfs.kubernetes_secret_v1.seaweedfs_s3_config
}

moved {
  from = kubernetes_config_map_v1.seaweedfs_scripts
  to   = module.seaweedfs.kubernetes_config_map_v1.seaweedfs_scripts
}

moved {
  from = kubernetes_persistent_volume_claim_v1.seaweedfs_data
  to   = module.seaweedfs.kubernetes_persistent_volume_claim_v1.seaweedfs_data
}

moved {
  from = kubernetes_deployment_v1.seaweedfs
  to   = module.seaweedfs.kubernetes_deployment_v1.seaweedfs
}

moved {
  from = kubernetes_cron_job_v1.seaweedfs_tier_move
  to   = module.seaweedfs.kubernetes_cron_job_v1.seaweedfs_tier_move
}

moved {
  from = module.seaweedfs_vpa
  to   = module.seaweedfs.module.vpa
}

moved {
  from = kubernetes_service_v1.seaweedfs
  to   = module.seaweedfs.kubernetes_service_v1.seaweedfs
}

moved {
  from = kubernetes_ingress_v1.s3_vinnel_cloud
  to   = module.seaweedfs.kubernetes_ingress_v1.s3_vinnel_cloud
}

moved {
  from = kubernetes_ingress_v1.seaweed_vinnel_cloud
  to   = module.seaweedfs.kubernetes_ingress_v1.seaweed_vinnel_cloud
}

moved {
  from = kubernetes_namespace_v1.backup
  to   = module.platform_backup.kubernetes_namespace_v1.backup
}

moved {
  from = kubernetes_secret_v1.s3_backup_credentials
  to   = module.platform_backup.kubernetes_secret_v1.s3_backup_credentials
}

moved {
  from = helm_release.kanister
  to   = module.platform_kanister.helm_release.kanister
}

moved {
  from = kubectl_manifest.kanister_s3_profile
  to   = module.platform_kanister.kubectl_manifest.kanister_s3_profile
}

moved {
  from = kubectl_manifest.snapshot_controller
  to   = module.platform_snapshot_controller.kubectl_manifest.snapshot_controller
}

moved {
  from = aws_s3_bucket.velero
  to   = module.platform_velero.aws_s3_bucket.velero
}

moved {
  from = kubernetes_secret_v1.velero_s3_credentials
  to   = module.platform_velero.kubernetes_secret_v1.velero_s3_credentials
}

moved {
  from = helm_release.velero
  to   = module.platform_velero.helm_release.velero
}

moved {
  from = kubernetes_service_account_v1.job_reaper
  to   = module.platform_job_reaper.kubernetes_service_account_v1.job_reaper
}

moved {
  from = kubernetes_cluster_role_v1.job_reaper
  to   = module.platform_job_reaper.kubernetes_cluster_role_v1.job_reaper
}

moved {
  from = kubernetes_cluster_role_binding_v1.job_reaper
  to   = module.platform_job_reaper.kubernetes_cluster_role_binding_v1.job_reaper
}

moved {
  from = kubernetes_cron_job_v1.job_reaper
  to   = module.platform_job_reaper.kubernetes_cron_job_v1.job_reaper
}

moved {
  from = helm_release.chaos_mesh
  to   = module.platform_chaos_mesh.helm_release.chaos_mesh
}

moved {
  from = kubectl_manifest.chaos_pod_kill_sites
  to   = module.platform_chaos_mesh.kubectl_manifest.chaos_pod_kill_sites
}

moved {
  from = kubectl_manifest.chaos_stress_sites
  to   = module.platform_chaos_mesh.kubectl_manifest.chaos_stress_sites
}

moved {
  from = helm_release.cilium
  to   = module.platform_cni.helm_release.cilium
}

moved {
  from = cloudflare_dns_record.hubble_vinnel_cloud
  to   = module.platform_cni.cloudflare_dns_record.hubble_vinnel_cloud
}

moved {
  from = kubernetes_ingress_v1.hubble_vinnel_cloud
  to   = module.platform_cni.kubernetes_ingress_v1.hubble_vinnel_cloud
}

moved {
  from = helm_release.trivy_operator
  to   = module.platform_trivy.helm_release.trivy_operator
}

moved {
  from = module.trivy_operator_vpa
  to   = module.platform_trivy.module.vpa
}

moved {
  from = signoz_rule.critical_vulnerability_found
  to   = module.platform_trivy.signoz_rule.critical_vulnerability_found
}

moved {
  from = signoz_rule.exposed_secret_found
  to   = module.platform_trivy.signoz_rule.exposed_secret_found
}

moved {
  from = aws_s3_bucket.terraform_provider_mirror
  to   = module.platform_terraform_mirror.aws_s3_bucket.terraform_provider_mirror
}

moved {
  from = aws_s3_bucket_policy.terraform_provider_mirror_public_read
  to   = module.platform_terraform_mirror.aws_s3_bucket_policy.terraform_provider_mirror_public_read
}

moved {
  from = helm_release.signoz
  to   = module.observability_signoz.helm_release.signoz
}

moved {
  from = helm_release.k8s_infra
  to   = module.observability_signoz.helm_release.k8s_infra
}

moved {
  from = kubernetes_cluster_role_v1.otel_agent_metrics
  to   = module.observability_signoz.kubernetes_cluster_role_v1.otel_agent_metrics
}

moved {
  from = kubernetes_cluster_role_binding_v1.otel_agent_metrics
  to   = module.observability_signoz.kubernetes_cluster_role_binding_v1.otel_agent_metrics
}

moved {
  from = cloudflare_dns_record.signoz_vinnel_cloud
  to   = module.observability_signoz.cloudflare_dns_record.signoz_vinnel_cloud
}

moved {
  from = signoz_rule.node_not_ready
  to   = module.observability_signoz.signoz_rule.node_not_ready
}

moved {
  from = signoz_rule.pvc_almost_full
  to   = module.observability_signoz.signoz_rule.pvc_almost_full
}

moved {
  from = signoz_rule.certificate_expiring_soon
  to   = module.observability_signoz.signoz_rule.certificate_expiring_soon
}

moved {
  from = signoz_rule.workload_degraded
  to   = module.observability_signoz.signoz_rule.workload_degraded
}

moved {
  from = kubernetes_ingress_v1.signoz_vinnel_cloud
  to   = module.observability_signoz.kubernetes_ingress_v1.signoz_vinnel_cloud
}

moved {
  from = kubernetes_ingress_v1.signoz_api_vinnel_cloud
  to   = module.observability_signoz.kubernetes_ingress_v1.signoz_api_vinnel_cloud
}

moved {
  from = kubernetes_namespace_v1.observability
  to   = module.observability_signoz.kubernetes_namespace_v1.observability
}

moved {
  from = signoz_dashboard.dashboard
  to   = module.observability_signoz_dashboards.signoz_dashboard.dashboard
}

moved {
  from = signoz_dashboard.service_status
  to   = module.observability_signoz_dashboards.signoz_dashboard.service_status
}

moved {
  from = signoz_dashboard.container_security
  to   = module.observability_signoz_dashboards.signoz_dashboard.container_security
}

moved {
  from = cloudflare_dns_record.status_vinnel_cloud
  to   = module.observability_betterstack.cloudflare_dns_record.status_vinnel_cloud
}

moved {
  from = kubernetes_ingress_v1.status_vinnel_cloud
  to   = module.observability_betterstack.kubernetes_ingress_v1.status_vinnel_cloud
}

moved {
  from = kubernetes_namespace_v1.auth
  to   = module.identity_authelia.kubernetes_namespace_v1.auth
}

moved {
  from = cloudflare_dns_record.auth_vin_moe
  to   = module.identity_authelia.cloudflare_dns_record.auth_vin_moe
}

moved {
  from = random_password.authelia_session_secret
  to   = module.identity_authelia.random_password.authelia_session_secret
}

moved {
  from = random_password.authelia_storage_encryption_key
  to   = module.identity_authelia.random_password.authelia_storage_encryption_key
}

moved {
  from = random_password.authelia_oidc_hmac_secret
  to   = module.identity_authelia.random_password.authelia_oidc_hmac_secret
}

moved {
  from = random_password.authelia_admin_password
  to   = module.identity_authelia.random_password.authelia_admin_password
}

moved {
  from = random_password.netbird_dashboard_oidc_client_secret
  to   = module.identity_authelia.random_password.netbird_dashboard_oidc_client_secret
}

moved {
  from = tls_private_key.authelia_oidc_issuer
  to   = module.identity_authelia.tls_private_key.authelia_oidc_issuer
}

moved {
  from = kubernetes_secret_v1.authelia_config
  to   = module.identity_authelia.kubernetes_secret_v1.authelia_config
}

moved {
  from = kubernetes_secret_v1.authelia_users_database
  to   = module.identity_authelia.kubernetes_secret_v1.authelia_users_database
}

moved {
  from = kubernetes_secret_v1.authelia_smtp_credentials
  to   = module.identity_authelia.kubernetes_secret_v1.authelia_smtp_credentials
}

moved {
  from = kubernetes_persistent_volume_claim_v1.authelia
  to   = module.identity_authelia.kubernetes_persistent_volume_claim_v1.authelia
}

moved {
  from = kubernetes_deployment_v1.authelia
  to   = module.identity_authelia.kubernetes_deployment_v1.authelia
}

moved {
  from = module.authelia_vpa
  to   = module.identity_authelia.module.vpa
}

moved {
  from = kubernetes_service_v1.authelia
  to   = module.identity_authelia.kubernetes_service_v1.authelia
}

moved {
  from = kubernetes_ingress_v1.authelia
  to   = module.identity_authelia.kubernetes_ingress_v1.authelia
}

moved {
  from = kubernetes_pod_disruption_budget_v1.vinnel_cloud_auth
  to   = module.identity_auth_portal.kubernetes_pod_disruption_budget_v1.vinnel_cloud_auth
}

moved {
  from = kubernetes_deployment_v1.vinnel_cloud_auth
  to   = module.identity_auth_portal.kubernetes_deployment_v1.vinnel_cloud_auth
}

moved {
  from = module.vinnel_cloud_auth_vpa
  to   = module.identity_auth_portal.module.vpa
}

moved {
  from = kubernetes_service_v1.vinnel_cloud_auth
  to   = module.identity_auth_portal.kubernetes_service_v1.vinnel_cloud_auth
}

moved {
  from = kubernetes_ingress_v1.vinnel_cloud_auth
  to   = module.identity_auth_portal.kubernetes_ingress_v1.vinnel_cloud_auth
}

moved {
  from = kubernetes_namespace_v1.proxy
  to   = module.proxy_netbird.kubernetes_namespace_v1.proxy
}

moved {
  from = netbird_user.ida
  to   = module.proxy_netbird.netbird_user.ida
}

moved {
  from = netbird_account_settings.main
  to   = module.proxy_netbird.netbird_account_settings.main
}

moved {
  from = netbird_group.devices
  to   = module.proxy_netbird.netbird_group.devices
}

moved {
  from = netbird_group.adguard
  to   = module.proxy_netbird.netbird_group.adguard
}

moved {
  from = netbird_group.iot
  to   = module.proxy_netbird.netbird_group.iot
}

moved {
  from = netbird_policy.devices_dns_udp_to_services
  to   = module.proxy_netbird.netbird_policy.devices_dns_udp_to_services
}

moved {
  from = netbird_policy.devices_dns_tcp_to_services
  to   = module.proxy_netbird.netbird_policy.devices_dns_tcp_to_services
}

moved {
  from = netbird_policy.default
  to   = module.proxy_netbird.netbird_policy.default
}

moved {
  from = cloudflare_dns_record.proxy_vinnel_cloud
  to   = module.proxy_netbird.cloudflare_dns_record.proxy_vinnel_cloud
}

moved {
  from = cloudflare_dns_record.netbird_vinnel_cloud
  to   = module.proxy_netbird.cloudflare_dns_record.netbird_vinnel_cloud
}

moved {
  from = random_password.netbird_relay_auth_secret
  to   = module.proxy_netbird.random_password.netbird_relay_auth_secret
}

moved {
  from = random_id.netbird_datastore_enc_key
  to   = module.proxy_netbird.random_id.netbird_datastore_enc_key
}

moved {
  from = kubernetes_secret_v1.netbird_secrets
  to   = module.proxy_netbird.kubernetes_secret_v1.netbird_secrets
}

moved {
  from = kubernetes_ingress_v1.netbird_dashboard_http
  to   = module.proxy_netbird.kubernetes_ingress_v1.netbird_dashboard_http
}

moved {
  from = kubernetes_ingress_v1.netbird_api_http
  to   = module.proxy_netbird.kubernetes_ingress_v1.netbird_api_http
}

moved {
  from = kubernetes_ingress_v1.netbird_grpc
  to   = module.proxy_netbird.kubernetes_ingress_v1.netbird_grpc
}

moved {
  from = kubernetes_secret_v1.netbird_management_config
  to   = module.proxy_netbird.kubernetes_secret_v1.netbird_management_config
}

moved {
  from = kubernetes_persistent_volume_claim_v1.netbird_management
  to   = module.proxy_netbird.kubernetes_persistent_volume_claim_v1.netbird_management
}

moved {
  from = kubernetes_deployment_v1.netbird_management
  to   = module.proxy_netbird.kubernetes_deployment_v1.netbird_management
}

moved {
  from = module.netbird_management_vpa
  to   = module.proxy_netbird.module.management_vpa
}

moved {
  from = kubernetes_service_v1.netbird_management
  to   = module.proxy_netbird.kubernetes_service_v1.netbird_management
}

moved {
  from = kubernetes_deployment_v1.netbird_dashboard
  to   = module.proxy_netbird.kubernetes_deployment_v1.netbird_dashboard
}

moved {
  from = module.netbird_dashboard_vpa
  to   = module.proxy_netbird.module.dashboard_vpa
}

moved {
  from = kubernetes_service_v1.netbird_dashboard
  to   = module.proxy_netbird.kubernetes_service_v1.netbird_dashboard
}

moved {
  from = kubernetes_deployment_v1.netbird_relay
  to   = module.proxy_netbird.kubernetes_deployment_v1.netbird_relay
}

moved {
  from = module.netbird_relay_vpa
  to   = module.proxy_netbird.module.relay_vpa
}

moved {
  from = kubernetes_service_v1.netbird_relay
  to   = module.proxy_netbird.kubernetes_service_v1.netbird_relay
}

moved {
  from = kubernetes_deployment_v1.netbird_signal
  to   = module.proxy_netbird.kubernetes_deployment_v1.netbird_signal
}

moved {
  from = module.netbird_signal_vpa
  to   = module.proxy_netbird.module.signal_vpa
}

moved {
  from = kubernetes_service_v1.netbird_signal
  to   = module.proxy_netbird.kubernetes_service_v1.netbird_signal
}

moved {
  from = kubernetes_namespace_v1.dns
  to   = module.adguard.kubernetes_namespace_v1.dns
}

moved {
  from = cloudflare_dns_record.adguard_admin_vinnel_cloud
  to   = module.adguard.cloudflare_dns_record.adguard_admin_vinnel_cloud
}

moved {
  from = kubernetes_config_map_v1.adguard_config_template
  to   = module.adguard.kubernetes_config_map_v1.adguard_config_template
}

moved {
  from = netbird_setup_key.adguard
  to   = module.adguard.netbird_setup_key.adguard
}

moved {
  from = kubernetes_secret_v1.adguard_netbird_setup_keys
  to   = module.adguard.kubernetes_secret_v1.adguard_netbird_setup_keys
}

moved {
  from = kubernetes_service_v1.adguard_headless
  to   = module.adguard.kubernetes_service_v1.adguard_headless
}

moved {
  from = kubernetes_stateful_set_v1.adguard
  to   = module.adguard.kubernetes_stateful_set_v1.adguard
}

moved {
  from = kubernetes_pod_disruption_budget_v1.adguard
  to   = module.adguard.kubernetes_pod_disruption_budget_v1.adguard
}

moved {
  from = module.adguard_vpa
  to   = module.adguard.module.vpa
}

moved {
  from = kubernetes_service_v1.adguard
  to   = module.adguard.kubernetes_service_v1.adguard
}

moved {
  from = kubernetes_ingress_v1.adguard_admin_vinnel_cloud
  to   = module.adguard.kubernetes_ingress_v1.adguard_admin_vinnel_cloud
}

moved {
  from = netbird_nameserver_group.adguard_devices
  to   = module.adguard.netbird_nameserver_group.adguard_devices
}

moved {
  from = cloudflare_dns_record.resend_dkim_vinnel_cloud
  to   = module.mail.cloudflare_dns_record.resend_dkim_vinnel_cloud
}

moved {
  from = cloudflare_dns_record.resend_mx_vinnel_cloud
  to   = module.mail.cloudflare_dns_record.resend_mx_vinnel_cloud
}

moved {
  from = cloudflare_dns_record.resend_spf_vinnel_cloud
  to   = module.mail.cloudflare_dns_record.resend_spf_vinnel_cloud
}

moved {
  from = cloudflare_dns_record.resend_tracking_vinnel_cloud
  to   = module.mail.cloudflare_dns_record.resend_tracking_vinnel_cloud
}

moved {
  from = kubernetes_namespace_v1.miniflux
  to   = module.miniflux.kubernetes_namespace_v1.miniflux
}

moved {
  from = cloudflare_dns_record.rss_vinnel_cloud
  to   = module.miniflux.cloudflare_dns_record.rss_vinnel_cloud
}

moved {
  from = random_password.miniflux_admin_password
  to   = module.miniflux.random_password.miniflux_admin_password
}

moved {
  from = random_password.miniflux_db_password
  to   = module.miniflux.random_password.miniflux_db_password
}

moved {
  from = kubernetes_secret_v1.miniflux
  to   = module.miniflux.kubernetes_secret_v1.miniflux
}

moved {
  from = kubernetes_service_v1.miniflux_postgres
  to   = module.miniflux.kubernetes_service_v1.miniflux_postgres
}

moved {
  from = kubernetes_stateful_set_v1.miniflux_postgres
  to   = module.miniflux.kubernetes_stateful_set_v1.miniflux_postgres
}

moved {
  from = module.miniflux_postgres_vpa
  to   = module.miniflux.module.miniflux_postgres_vpa
}

moved {
  from = kubernetes_deployment_v1.miniflux
  to   = module.miniflux.kubernetes_deployment_v1.miniflux
}

moved {
  from = module.miniflux_vpa
  to   = module.miniflux.module.miniflux_vpa
}

moved {
  from = kubernetes_service_v1.miniflux
  to   = module.miniflux.kubernetes_service_v1.miniflux
}

moved {
  from = kubernetes_ingress_v1.rss_vinnel_cloud
  to   = module.miniflux.kubernetes_ingress_v1.rss_vinnel_cloud
}

moved {
  from = kubernetes_namespace_v1.registry
  to   = module.registry_cache.kubernetes_namespace_v1.registry
}

moved {
  from = cloudflare_dns_record.mirror_vinnel_cloud
  to   = module.registry_cache.cloudflare_dns_record.mirror_vinnel_cloud
}

moved {
  from = random_password.registry_cache
  to   = module.registry_cache.random_password.registry_cache
}

moved {
  from = kubernetes_secret_v1.registry_cache_config
  to   = module.registry_cache.kubernetes_secret_v1.registry_cache_config
}

moved {
  from = kubernetes_persistent_volume_claim_v1.registry_cache
  to   = module.registry_cache.kubernetes_persistent_volume_claim_v1.registry_cache
}

moved {
  from = kubernetes_deployment_v1.registry_cache
  to   = module.registry_cache.kubernetes_deployment_v1.registry_cache
}

moved {
  from = module.registry_cache_vpa
  to   = module.registry_cache.module.registry_cache_vpa
}

moved {
  from = kubernetes_service_v1.registry_cache
  to   = module.registry_cache.kubernetes_service_v1.registry_cache
}

moved {
  from = kubernetes_ingress_v1.mirror_vinnel_cloud
  to   = module.registry_cache.kubernetes_ingress_v1.mirror_vinnel_cloud
}

moved {
  from = gitlab_project_variable.registry_cache_user
  to   = module.registry_cache.gitlab_project_variable.registry_cache_user
}

moved {
  from = gitlab_project_variable.registry_cache_password
  to   = module.registry_cache.gitlab_project_variable.registry_cache_password
}

moved {
  from = cloudflare_dns_record.velero_vinnel_cloud
  to   = module.velero_ui.cloudflare_dns_record.velero_vinnel_cloud
}

moved {
  from = random_password.velero_ui_oidc_client_secret
  to   = module.velero_ui.random_password.velero_ui_oidc_client_secret
}

moved {
  from = random_password.velero_ui_auth_secret_passphrase
  to   = module.velero_ui.random_password.velero_ui_auth_secret_passphrase
}

moved {
  from = kubernetes_service_account_v1.velero_ui
  to   = module.velero_ui.kubernetes_service_account_v1.velero_ui
}

moved {
  from = kubernetes_cluster_role_v1.velero_ui
  to   = module.velero_ui.kubernetes_cluster_role_v1.velero_ui
}

moved {
  from = kubernetes_cluster_role_binding_v1.velero_ui
  to   = module.velero_ui.kubernetes_cluster_role_binding_v1.velero_ui
}

moved {
  from = kubernetes_role_v1.velero_ui
  to   = module.velero_ui.kubernetes_role_v1.velero_ui
}

moved {
  from = kubernetes_role_binding_v1.velero_ui
  to   = module.velero_ui.kubernetes_role_binding_v1.velero_ui
}

moved {
  from = kubernetes_config_map_v1.velero_ui_policies
  to   = module.velero_ui.kubernetes_config_map_v1.velero_ui_policies
}

moved {
  from = kubernetes_deployment_v1.velero_ui
  to   = module.velero_ui.kubernetes_deployment_v1.velero_ui
}

moved {
  from = kubernetes_secret_v1.velero_ui_secrets
  to   = module.velero_ui.kubernetes_secret_v1.velero_ui_secrets
}

moved {
  from = module.velero_ui_vpa
  to   = module.velero_ui.module.velero_ui_vpa
}

moved {
  from = kubernetes_service_v1.velero_ui
  to   = module.velero_ui.kubernetes_service_v1.velero_ui
}

moved {
  from = kubernetes_ingress_v1.velero_vinnel_cloud
  to   = module.velero_ui.kubernetes_ingress_v1.velero_vinnel_cloud
}

moved {
  from = kubernetes_namespace_v1.vin_moe
  to   = module.vin_moe.kubernetes_namespace_v1.vin_moe
}

moved {
  from = kubernetes_secret_v1.registry_dockerconfig_vin_moe
  to   = module.vin_moe.kubernetes_secret_v1.registry_dockerconfig_vin_moe
}

moved {
  from = module.vin_moe_site
  to   = module.vin_moe.module.vin_moe_site
}

moved {
  from = kubernetes_namespace_v1.monke_academy
  to   = module.monke_academy.kubernetes_namespace_v1.monke_academy
}

moved {
  from = kubernetes_secret_v1.registry_dockerconfig_monke_academy
  to   = module.monke_academy.kubernetes_secret_v1.registry_dockerconfig_monke_academy
}

moved {
  from = module.monke_academy_site
  to   = module.monke_academy.module.monke_academy_site
}

moved {
  from = kubernetes_namespace_v1.vinnel_cloud
  to   = module.vinnel_cloud.kubernetes_namespace_v1.vinnel_cloud
}

moved {
  from = kubernetes_secret_v1.registry_dockerconfig_vinnel_cloud
  to   = module.vinnel_cloud.kubernetes_secret_v1.registry_dockerconfig_vinnel_cloud
}

moved {
  from = module.vinnel_cloud_site
  to   = module.vinnel_cloud.module.vinnel_cloud_site
}

moved {
  from = kubernetes_namespace_v1.forge
  to   = module.gitlab.kubernetes_namespace_v1.forge
}

moved {
  from = cloudflare_dns_record.gitlab_vinnel_cloud
  to   = module.gitlab.cloudflare_dns_record.gitlab_vinnel_cloud
}

moved {
  from = cloudflare_dns_record.artifacts_vinnel_cloud
  to   = module.gitlab.cloudflare_dns_record.artifacts_vinnel_cloud
}

moved {
  from = random_password.gitlab_root_password
  to   = module.gitlab.random_password.gitlab_root_password
}

moved {
  from = kubernetes_secret_v1.gitlab_credentials
  to   = module.gitlab.kubernetes_secret_v1.gitlab_credentials
}

moved {
  from = kubernetes_persistent_volume_claim_v1.gitlab_config
  to   = module.gitlab.kubernetes_persistent_volume_claim_v1.gitlab_config
}

moved {
  from = kubernetes_persistent_volume_claim_v1.gitlab_logs
  to   = module.gitlab.kubernetes_persistent_volume_claim_v1.gitlab_logs
}

moved {
  from = kubernetes_persistent_volume_claim_v1.gitlab_data
  to   = module.gitlab.kubernetes_persistent_volume_claim_v1.gitlab_data
}

moved {
  from = kubernetes_deployment_v1.gitlab
  to   = module.gitlab.kubernetes_deployment_v1.gitlab
}

moved {
  from = module.gitlab_vpa
  to   = module.gitlab.module.gitlab_vpa
}

moved {
  from = kubernetes_service_v1.gitlab
  to   = module.gitlab.kubernetes_service_v1.gitlab
}

moved {
  from = kubernetes_ingress_v1.gitlab_vinnel_cloud
  to   = module.gitlab.kubernetes_ingress_v1.gitlab_vinnel_cloud
}

moved {
  from = kubernetes_ingress_v1.artifacts_vinnel_cloud
  to   = module.gitlab.kubernetes_ingress_v1.artifacts_vinnel_cloud
}

moved {
  from = kubernetes_service_account_v1.gitlab_runner
  to   = module.gitlab.kubernetes_service_account_v1.gitlab_runner
}

moved {
  from = kubernetes_role_v1.gitlab_runner
  to   = module.gitlab.kubernetes_role_v1.gitlab_runner
}

moved {
  from = kubernetes_role_binding_v1.gitlab_runner
  to   = module.gitlab.kubernetes_role_binding_v1.gitlab_runner
}

moved {
  from = gitlab_project_deploy_token.registry
  to   = module.gitlab.gitlab_project_deploy_token.registry
}

moved {
  from = kubernetes_secret_v1.registry_dockerconfig_gitlab
  to   = module.gitlab.kubernetes_secret_v1.registry_dockerconfig_gitlab
}

moved {
  from = gitlab_group_dependency_proxy.vinnel_cloud
  to   = module.gitlab.gitlab_group_dependency_proxy.vinnel_cloud
}

moved {
  from = gitlab_user_runner.gaia
  to   = module.gitlab.gitlab_user_runner.gaia
}

moved {
  from = kubernetes_secret_v1.gitlab_runner_config
  to   = module.gitlab.kubernetes_secret_v1.gitlab_runner_config
}

moved {
  from = kubernetes_deployment_v1.gitlab_runner
  to   = module.gitlab.kubernetes_deployment_v1.gitlab_runner
}

moved {
  from = module.gitlab_runner_vpa
  to   = module.gitlab.module.gitlab_runner_vpa
}

moved {
  from = gitlab_user_runner.gaia_privileged_build
  to   = module.gitlab.gitlab_user_runner.gaia_privileged_build
}

moved {
  from = kubernetes_secret_v1.gitlab_runner_privileged_config
  to   = module.gitlab.kubernetes_secret_v1.gitlab_runner_privileged_config
}

moved {
  from = kubernetes_deployment_v1.gitlab_runner_privileged
  to   = module.gitlab.kubernetes_deployment_v1.gitlab_runner_privileged
}

moved {
  from = module.gitlab_runner_privileged_vpa
  to   = module.gitlab.module.gitlab_runner_privileged_vpa
}

moved {
  from = gitlab_group.vinnel_cloud
  to   = module.gitlab.gitlab_group.vinnel_cloud
}

moved {
  from = gitlab_project.gaia
  to   = module.gitlab.gitlab_project.gaia
}

moved {
  from = gitlab_branch.pre
  to   = module.gitlab.gitlab_branch.pre
}

moved {
  from = gitlab_branch_protection.prd
  to   = module.gitlab.gitlab_branch_protection.prd
}

moved {
  from = gitlab_project_access_token.ci_bot
  to   = module.gitlab.gitlab_project_access_token.ci_bot
}

moved {
  from = gitlab_project_variable.ci_bot_token
  to   = module.gitlab.gitlab_project_variable.ci_bot_token
}

moved {
  from = gitlab_project_variable.gh_api_token
  to   = module.gitlab.gitlab_project_variable.gh_api_token
}

moved {
  from = gitlab_project_variable.tfc_api_token
  to   = module.gitlab.gitlab_project_variable.tfc_api_token
}

moved {
  from = gitlab_pipeline_trigger.reconcile
  to   = module.gitlab.gitlab_pipeline_trigger.reconcile
}

moved {
  from = gitlab_project_variable.reconcile_trigger_token
  to   = module.gitlab.gitlab_project_variable.reconcile_trigger_token
}

moved {
  from = gitlab_pipeline_schedule.ci_runner_scan
  to   = module.gitlab.gitlab_pipeline_schedule.ci_runner_scan
}

moved {
  from = gitlab_project_variable.site_deploy_kubeconfig
  to   = module.gitlab.gitlab_project_variable.site_deploy_kubeconfig
}

moved {
  from = gitlab_project_variable.cf_api_token
  to   = module.gitlab.gitlab_project_variable.cf_api_token
}

moved {
  from = kubernetes_namespace_v1.files
  to   = module.nextcloud.kubernetes_namespace_v1.files
}

moved {
  from = cloudflare_dns_record.cloud_vinnel_cloud
  to   = module.nextcloud.cloudflare_dns_record.cloud_vinnel_cloud
}

moved {
  from = random_password.nextcloud_admin_password
  to   = module.nextcloud.random_password.nextcloud_admin_password
}

moved {
  from = random_password.nextcloud_oidc_client_secret
  to   = module.nextcloud.random_password.nextcloud_oidc_client_secret
}

moved {
  from = kubernetes_config_map_v1.nextcloud_setup
  to   = module.nextcloud.kubernetes_config_map_v1.nextcloud_setup
}

moved {
  from = kubernetes_secret_v1.nextcloud_secrets
  to   = module.nextcloud.kubernetes_secret_v1.nextcloud_secrets
}

moved {
  from = kubernetes_persistent_volume_claim_v1.nextcloud
  to   = module.nextcloud.kubernetes_persistent_volume_claim_v1.nextcloud
}

moved {
  from = kubernetes_deployment_v1.nextcloud
  to   = module.nextcloud.kubernetes_deployment_v1.nextcloud
}

moved {
  from = module.nextcloud_vpa
  to   = module.nextcloud.module.nextcloud_vpa
}

moved {
  from = kubernetes_service_v1.nextcloud
  to   = module.nextcloud.kubernetes_service_v1.nextcloud
}

moved {
  from = kubernetes_ingress_v1.cloud_vinnel_cloud
  to   = module.nextcloud.kubernetes_ingress_v1.cloud_vinnel_cloud
}

moved {
  from = kubernetes_job_v1.nextcloud_mega_import
  to   = module.nextcloud.kubernetes_job_v1.nextcloud_mega_import
}

moved {
  from = kubernetes_ingress_v1.cloud_api_vinnel_cloud
  to   = module.nextcloud.kubernetes_ingress_v1.cloud_api_vinnel_cloud
}

moved {
  from = cloudflare_dns_record.shell_vinnel_cloud
  to   = module.shell.cloudflare_dns_record.shell_vinnel_cloud
}

moved {
  from = random_password.shell_ttyd
  to   = module.shell.random_password.shell_ttyd
}

moved {
  from = kubernetes_secret_v1.shell_ttyd_credentials
  to   = module.shell.kubernetes_secret_v1.shell_ttyd_credentials
}

moved {
  from = kubernetes_deployment_v1.vinnel_cloud_shell
  to   = module.shell.kubernetes_deployment_v1.vinnel_cloud_shell
}

moved {
  from = module.vinnel_cloud_shell_vpa
  to   = module.shell.module.vinnel_cloud_shell_vpa
}

moved {
  from = kubernetes_service_v1.vinnel_cloud_shell
  to   = module.shell.kubernetes_service_v1.vinnel_cloud_shell
}

moved {
  from = kubernetes_ingress_v1.shell_vinnel_cloud
  to   = module.shell.kubernetes_ingress_v1.shell_vinnel_cloud
}

moved {
  from = kubernetes_namespace_v1.games
  to   = module.minecraft.kubernetes_namespace_v1.games
}

moved {
  from = cloudflare_dns_record.mc_vin_moe
  to   = module.minecraft.cloudflare_dns_record.mc_vin_moe
}

moved {
  from = random_password.minecraft_rcon
  to   = module.minecraft.random_password.minecraft_rcon
}

moved {
  from = kubernetes_secret_v1.minecraft
  to   = module.minecraft.kubernetes_secret_v1.minecraft
}

moved {
  from = kubernetes_secret_v1.minecraft_rcon_admin
  to   = module.minecraft.kubernetes_secret_v1.minecraft_rcon_admin
}

moved {
  from = kubernetes_persistent_volume_claim_v1.minecraft_data
  to   = module.minecraft.kubernetes_persistent_volume_claim_v1.minecraft_data
}

moved {
  from = kubernetes_deployment_v1.minecraft
  to   = module.minecraft.kubernetes_deployment_v1.minecraft
}

moved {
  from = module.minecraft_vpa
  to   = module.minecraft.module.minecraft_vpa
}

moved {
  from = cloudflare_dns_record.factory_vin_moe
  to   = module.satisfactory.cloudflare_dns_record.factory_vin_moe
}

moved {
  from = kubernetes_secret_v1.satisfactory_admin
  to   = module.satisfactory.kubernetes_secret_v1.satisfactory_admin
}

moved {
  from = kubernetes_persistent_volume_claim_v1.satisfactory_saves
  to   = module.satisfactory.kubernetes_persistent_volume_claim_v1.satisfactory_saves
}

moved {
  from = kubernetes_config_map_v1.satisfactory_saves_http_conf
  to   = module.satisfactory.kubernetes_config_map_v1.satisfactory_saves_http_conf
}

moved {
  from = kubernetes_service_v1.satisfactory_saves
  to   = module.satisfactory.kubernetes_service_v1.satisfactory_saves
}

moved {
  from = kubernetes_deployment_v1.satisfactory
  to   = module.satisfactory.kubernetes_deployment_v1.satisfactory
}

moved {
  from = module.satisfactory_vpa
  to   = module.satisfactory.module.satisfactory_vpa
}

moved {
  from = cloudflare_dns_record.admin_vinnel_cloud
  to   = module.admin.cloudflare_dns_record.admin_vinnel_cloud
}

moved {
  from = kubernetes_persistent_volume_claim_v1.vinnel_cloud_admin_blog
  to   = module.admin.kubernetes_persistent_volume_claim_v1.vinnel_cloud_admin_blog
}

moved {
  from = gitlab_project_access_token.admin_blog
  to   = module.admin.gitlab_project_access_token.admin_blog
}

moved {
  from = kubernetes_secret_v1.vinnel_cloud_admin_blog
  to   = module.admin.kubernetes_secret_v1.vinnel_cloud_admin_blog
}

moved {
  from = kubernetes_service_account_v1.vinnel_cloud_admin
  to   = module.admin.kubernetes_service_account_v1.vinnel_cloud_admin
}

moved {
  from = kubernetes_cluster_role_v1.vinnel_cloud_admin
  to   = module.admin.kubernetes_cluster_role_v1.vinnel_cloud_admin
}

moved {
  from = kubernetes_cluster_role_binding_v1.vinnel_cloud_admin
  to   = module.admin.kubernetes_cluster_role_binding_v1.vinnel_cloud_admin
}

moved {
  from = kubernetes_role_v1.vinnel_cloud_admin_gameserver_scale
  to   = module.admin.kubernetes_role_v1.vinnel_cloud_admin_gameserver_scale
}

moved {
  from = kubernetes_role_binding_v1.vinnel_cloud_admin_gameserver_scale
  to   = module.admin.kubernetes_role_binding_v1.vinnel_cloud_admin_gameserver_scale
}

moved {
  from = kubernetes_pod_disruption_budget_v1.vinnel_cloud_admin
  to   = module.admin.kubernetes_pod_disruption_budget_v1.vinnel_cloud_admin
}

moved {
  from = kubernetes_deployment_v1.vinnel_cloud_admin
  to   = module.admin.kubernetes_deployment_v1.vinnel_cloud_admin
}

moved {
  from = module.vinnel_cloud_admin_vpa
  to   = module.admin.module.vinnel_cloud_admin_vpa
}

moved {
  from = kubernetes_service_v1.vinnel_cloud_admin
  to   = module.admin.kubernetes_service_v1.vinnel_cloud_admin
}

moved {
  from = kubernetes_ingress_v1.vinnel_cloud_admin
  to   = module.admin.kubernetes_ingress_v1.vinnel_cloud_admin
}

moved {
  from = kubernetes_service_account_v1.ci_deployer
  to   = module.platform_ci.kubernetes_service_account_v1.ci_deployer
}

moved {
  from = kubernetes_cluster_role_v1.ci_deployer
  to   = module.platform_ci.kubernetes_cluster_role_v1.ci_deployer
}

moved {
  from = kubernetes_role_binding_v1.ci_deployer
  to   = module.platform_ci.kubernetes_role_binding_v1.ci_deployer
}

moved {
  from = kubernetes_secret_v1.ci_deployer_token
  to   = module.platform_ci.kubernetes_secret_v1.ci_deployer_token
}

moved {
  from = module.network_policy
  to   = module.platform_network_policy.module.network_policy
}

