variable "dockerhub_username" {
  type      = string
  sensitive = true
}

variable "dockerhub_access_token" {
  type      = string
  sensitive = true
}

variable "ghcr_username" {
  type      = string
  sensitive = true
}

variable "ghcr_access_token" {
  type      = string
  sensitive = true
}

variable "require_mfa" {
  type    = bool
  default = true
}
