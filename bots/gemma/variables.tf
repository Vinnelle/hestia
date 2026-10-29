variable "image" {
  description = "Digest-pinned image of Gemma, carrying chat, tor and the bot"
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

variable "search_url" {
  description = "Base URL of the SearXNG instance the bot's search tool asks, with its JSON format on"
  type        = string
}

variable "session" {
  description = "chat session id the bot sits in; the vin.moe party runners join vin-moe-party with a blank password"
  type        = string
  default     = "vin-moe-party"
}

variable "sign_password" {
  description = "Password the bot's chat signing identity (an AGE key made without the nick) is made from, with machine_id"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[A-Za-z0-9]{128,255}$", var.sign_password))
    error_message = "sign_password must be 128-255 letters and digits."
  }
}

variable "machine_id" {
  description = "Machine id mounted as /etc/machine-id, which chat makes the signing identity with alongside sign_password"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.machine_id))
    error_message = "machine_id must be 32 lowercase hex digits."
  }
}

variable "nick" {
  description = "Nick the bot uses in chat; its signing identity is made without it, so changing it keeps the bot's fingerprint"
  type        = string
  default     = "Gemma"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,24}$", var.nick))
    error_message = "nick must be 1-24 letters, digits, dots, dashes or underscores."
  }
}

variable "owner_fingerprint" {
  description = "Finlay's chat signing identity fingerprint, as :verify shows it; the bot tells the model which messages it signed"
  type        = string
  default     = "2601 2dc1 1ca1 6991 10df 4d61 68f4 2a7a"

  validation {
    condition     = can(regex("^[0-9a-f]{4}( [0-9a-f]{4}){7}$", var.owner_fingerprint))
    error_message = "owner_fingerprint must be eight groups of four lowercase hex digits."
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
