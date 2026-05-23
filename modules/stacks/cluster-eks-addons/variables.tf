variable "cluster_name" { type = string }
variable "aws_region" { type = string }
variable "eks_endpoint" { type = string }
variable "eks_ca_certificate" { type = string }
variable "interruption_handling_queue" { type = string }
variable "karpenter_node_role_name" { type = string }
variable "vpc_id" { type = string }
variable "web_acl_arn" { type = string }
