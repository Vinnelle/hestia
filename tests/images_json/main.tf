terraform {
  required_version = ">= 1.9.0"
}

locals {
  images = jsondecode(file("${path.module}/../../sites/images.json"))
}

output "images" {
  value = local.images
}
