variable "cluster_name" {
  description = "Name of EKS Cluster"
  type        = string
}

variable "node_group_name" {
  description = "Name of node group"
  type        = string
}

variable "subnet_ids" {
  description = "ID list of subnet"
  type        = list(string)
}

variable "ami_type" {
  description = "Type of AMI"
  type        = string
  validation {
    condition = contains([
      "AL2_x86_64", "AL2_x86_64_GPU", "AL2_ARM_64", "CUSTOM",
      "BOTTLEROCKET_ARM_64", "BOTTLEROCKET_x86_64",
      "BOTTLEROCKET_ARM_64_FIPS", "BOTTLEROCKET_x86_64_FIPS",
      "BOTTLEROCKET_ARM_64_NVIDIA", "BOTTLEROCKET_x86_64_NVIDIA",
      "BOTTLEROCKET_ARM_64_NVIDIA_FIPS", "BOTTLEROCKET_x86_64_NVIDIA_FIPS",
      "WINDOWS_CORE_2019_x86_64", "WINDOWS_FULL_2019_x86_64",
      "WINDOWS_CORE_2022_x86_64", "WINDOWS_FULL_2022_x86_64",
      "WINDOWS_CORE_2025_x86_64", "WINDOWS_FULL_2025_x86_64",
      "AL2023_x86_64_STANDARD", "AL2023_ARM_64_STANDARD",
      "AL2023_x86_64_NEURON", "AL2023_x86_64_NVIDIA", "AL2023_ARM_64_NVIDIA"
    ], var.ami_type)
    error_message = "amiType does not match. check: https://docs.aws.amazon.com/eks/latest/APIReference/API_Nodegroup.html#AmazonEKS-Type-Nodegroup-amiType"
  }
}

variable "instance_types" {
  description = "List of instance type"
  type        = list(string)
}

variable "capacity_type" {
  description = "Node Capacity Type"
  type        = string
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "Valid value: <ON_DEMAND | SPOT>"
  }
}

variable "disk_size" {
  description = "Disk size for each worker node"
  type        = number
  default     = 20
}

variable "scaling" {
  description = "Scaling Capacity"
  type = object({
    desired_size = number
    min_size     = number
    max_size     = number
  })
}

variable "labels" {
  description = "Node labels"
  type        = map(string)
}

variable "taints" {
  description = "Taints for rule"
  type = map(object({
    key    = string
    value  = optional(string)
    effect = string
  }))

  validation {
    condition = alltrue([
      for _, v in var.taints :
      contains(["NO_SCHEDULE", "NO_EXECUTE", "PREFER_NO_SCHEDULE"], v.effect)
    ])
    error_message = "Valid effect: <NO_SCHEDULE | NO_EXECUTE | PREFER_NO_SCHEDULE>"
  }
}

variable "role_policy_attachment" {
  description = "Role policies to attach nodes"
  type        = set(string)
  default     = []
}
