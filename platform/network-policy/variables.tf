variable "telemetry_namespace" {
  description = "Namespace every policied namespace is allowed to ship telemetry to"
  type        = string
}

variable "mega_s4_endpoint_domain" {
  description = "MEGA S4 endpoint domain the backup namespace is allowed to reach, matching the root variable of the same name"
  type        = string
}
