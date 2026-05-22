variable "cluster_name" { type = string }
variable "aws_region" { type = string }
variable "vpc_cidr" { type = string }

variable "natgw_azs" {
  description = "NAT Gateway를 생성할 AZ 목록. ['a'] = 단일, ['a','c'] = 고가용성"
  type        = list(string)
  default     = ["a"]
}

variable "enable_full_vpce" {
  description = "true = Interface VPCE 풀셋 생성 (private mode 시 필요). false = S3 Gateway만 유지"
  type        = bool
  default     = false
}
