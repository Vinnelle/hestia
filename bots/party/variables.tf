variable "image" {
  description = "Digest-pinned party bot image, carrying chat, tor and the bot"
  type        = string
}

variable "registry_dockerconfigjson" {
  description = "dockerconfigjson that pulls from artifacts.vinnel.cloud"
  type        = string
  sensitive   = true
}

variable "llm_base_url" {
  description = "Base URL of the OpenAI-compatible API the bot asks, ending in /v1"
  type        = string
}

variable "llm_model" {
  description = "Model name to send to llm_base_url"
  type        = string
}

variable "llm_api_key" {
  description = "Bearer token for llm_base_url"
  type        = string
  sensitive   = true
}

variable "session" {
  description = "chat session id the bot sits in; the vin.moe party runners join vin-moe-party with a blank password"
  type        = string
  default     = "vin-moe-party"
}

variable "nick" {
  description = "Nick the bot uses in chat; its signing identity is derived from this and a generated password, so changing it changes the bot's fingerprint"
  type        = string
  default     = "vin-bot"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,24}$", var.nick))
    error_message = "nick must be 1-24 letters, digits, dots, dashes or underscores."
  }
}

variable "colour" {
  description = "Colour of the bot's nick in chat, as #RRGGBB"
  type        = string
  default     = "#f7b9d1"

  validation {
    condition     = can(regex("^#[0-9a-fA-F]{6}$", var.colour))
    error_message = "colour must be #RRGGBB."
  }
}
