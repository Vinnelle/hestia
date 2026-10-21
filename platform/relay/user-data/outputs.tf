output "content" {
  description = "Shell script the relay image runs at boot: nftables, wg0, metrics services, then the module lock"
  value       = local.content
  sensitive   = true
}
