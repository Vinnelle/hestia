# Isolated from the real root module deliberately: hestia/images.json is pure
# data (no provider needed to read it), and the root module needs live
# credentials/backend for almost everything else. Testing it here means
# `terraform test` never has to mock the cloud backend or the ~10 providers
# in providers.tf.
terraform {
  required_version = ">= 1.9.0"
}

locals {
  images = jsondecode(file("${path.module}/../../images.json"))
}

output "images" {
  value = local.images
}
