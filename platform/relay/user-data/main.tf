locals {
  counters = { for name, f in var.forwards : name => replace(name, "-", "_") }

  content = templatefile("${path.module}/relay-init.sh.tftpl", {
    nftables = templatefile("${path.module}/nftables.conf.tftpl", {
      wireguard_port = var.wireguard_port
      metrics_port   = var.metrics_port
      node_address   = var.node_address
      forwards       = var.forwards
      counters       = local.counters
    })
    metrics = templatefile("${path.module}/relay-metrics.sh.tftpl", {
      forwards = var.forwards
      counters = local.counters
    })
    port            = var.wireguard_port
    private_key     = var.private_key
    node_public_key = var.node_public_key
    relay_address   = var.relay_address
    node_address    = var.node_address
    metrics_port    = var.metrics_port
    summary         = join(" ", [for name, f in var.forwards : "${f.port}/${f.protocol}"])
  })
}
