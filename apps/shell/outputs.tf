output "ttyd_password" {
  description = "Password protecting the browser shell"
  value       = random_password.shell_ttyd.result
  sensitive   = true
}
