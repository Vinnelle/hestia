import {
  to = module.gitlab.gitlab_branch_protection.prd
  id = "vinnel-cloud/gaia:prd"
}

import {
  to = module.platform_terraform_mirror.aws_s3_bucket.terraform_provider_mirror
  id = "providers"
}

import {
  to = module.platform_velero.helm_release.velero
  id = "velero/velero"
}

import {
  to = module.proxy_netbird.netbird_user.ida
  id = "602cdb07-d95e-4014-8361-1c24136a8a25"
}

import {
  to = module.proxy_netbird.netbird_account_settings.main
  id = "d9jkfom7tkps73ehoj6g"
}
