terraform {
  required_version = ">= 1.9.0"
}

locals {
  rendered = yamldecode(templatefile("${path.module}/../../platform/vpa/resource/vpa.yaml.tftpl", {
    name        = "example"
    namespace   = "server"
    target_kind = "Deployment"
    target_name = "example"
    update_mode = "Initial"
    container_policies = [{
      container_name = "example"
      min_memory     = "1Gi"
      max_memory     = "2Gi"
    }]
  }))
}

output "rendered" {
  value = local.rendered
}
