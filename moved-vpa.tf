moved {
  from = kubectl_manifest.vinnel_cloud_admin_vpa
  to   = module.vinnel_cloud_admin_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.adguard_vpa
  to   = module.adguard_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.ntfy_vpa
  to   = module.ntfy_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.gitlab_vpa
  to   = module.gitlab_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.gitlab_runner_vpa
  to   = module.gitlab_runner_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.gitlab_runner_privileged_vpa
  to   = module.gitlab_runner_privileged_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.nextcloud_vpa
  to   = module.nextcloud_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.satisfactory_vpa
  to   = module.satisfactory_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.velero_ui_vpa
  to   = module.velero_ui_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.netbird_dashboard_vpa
  to   = module.netbird_dashboard_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.netbird_signal_vpa
  to   = module.netbird_signal_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.wwv_postgres_vpa
  to   = module.wwv_postgres_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.wwv_redis_vpa
  to   = module.wwv_redis_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.wwv_data_engine_vpa
  to   = module.wwv_data_engine_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.wwv_vpa
  to   = module.wwv_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.vinnel_cloud_shell_vpa
  to   = module.vinnel_cloud_shell_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.netbird_relay_vpa
  to   = module.netbird_relay_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.vinnel_cloud_auth_vpa
  to   = module.vinnel_cloud_auth_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.netbird_management_vpa
  to   = module.netbird_management_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.authelia_vpa
  to   = module.authelia_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.seaweedfs_vpa
  to   = module.seaweedfs_vpa.kubectl_manifest.this
}

moved {
  from = kubectl_manifest.minecraft_vpa
  to   = module.minecraft_vpa.kubectl_manifest.this
}
