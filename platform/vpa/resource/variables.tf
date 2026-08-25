variable "name" {
  description = "VerticalPodAutoscaler name"
  type        = string
}

variable "namespace" {
  description = "Namespace of the target workload"
  type        = string
}

variable "target_kind" {
  description = "Kind of the target workload"
  type        = string
  default     = "Deployment"

  validation {
    condition     = contains(["Deployment", "StatefulSet"], var.target_kind)
    error_message = "target_kind must be Deployment or StatefulSet."
  }
}

variable "target_name" {
  description = "Name of the target workload"
  type        = string
}

variable "update_mode" {
  description = "VPA updateMode (Off, Initial, Auto)"
  type        = string

  validation {
    condition     = contains(["Off", "Initial", "Auto"], var.update_mode)
    error_message = "update_mode must be Off, Initial, or Auto."
  }
}

variable "container_policies" {
  description = "Per-container memory bounds"
  type = list(object({
    container_name = string
    min_memory     = string
    max_memory     = string
  }))
}
