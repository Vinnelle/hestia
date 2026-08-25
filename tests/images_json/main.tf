terraform {
  required_version = ">= 1.9.0"
}

locals {
  images = merge(
    jsondecode(file("${path.module}/../../sites/site-images.json")),
    jsondecode(file("${path.module}/../../apps/app-images.json")),
    jsondecode(file("${path.module}/../../identity/identity-images.json")),
  )
}

output "images" {
  value = local.images
}
