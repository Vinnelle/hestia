variable "namespace" {
  description = "Namespace the Trivy operator runs in"
  type        = string
}

variable "signoz_alert_channels" {
  description = "SigNoz notification channels the vulnerability alerts route to"
  type        = list(string)
}

variable "signoz_notification_settings" {
  description = "SigNoz notification settings block shared by the alerting rules"
  type        = any
}
