variable "dockerhub_username" {
  description = "Docker Hub username used for the ECR pull-through cache secret."
  type        = string
  sensitive   = true
}

variable "dockerhub_access_token" {
  description = "Docker Hub access token used for the ECR pull-through cache secret."
  type        = string
  sensitive   = true
}

variable "ghcr_username" {
  description = "GitHub Container Registry username used for the ECR pull-through cache secret."
  type        = string
  sensitive   = true
}

variable "ghcr_access_token" {
  description = "GitHub Container Registry access token used for the ECR pull-through cache secret."
  type        = string
  sensitive   = true
}

variable "root_domain_name" {
  description = "Primary public DNS zone managed in Route 53."
  type        = string
  default     = "hive-wiki.com"
}

variable "certificate_subject_alternative_names" {
  description = "Additional DNS names to include in the shared ACM certificate."
  type        = list(string)
  default     = ["*.hive-wiki.com"]

  validation {
    condition     = length(var.certificate_subject_alternative_names) > 0
    error_message = "At least one subject alternative name must be provided."
  }
}
