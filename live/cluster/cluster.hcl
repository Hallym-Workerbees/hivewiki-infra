locals {
  cluster_name = "hivewiki-dev"
  environment  = "dev"
  aws_region   = "ap-northeast-2"
  vpc_cidr     = "10.1.0.0/16"

  state_bucket = "hivewiki-infra-state-bucket"

  # -------------------------------------------------------
  # Network toggles
  # -------------------------------------------------------

  # NAT Gateway AZs. 비용 절감 시 ["a"]로, 고가용성 시 ["a", "c"]
  natgw_azs = ["a"]

  # EKS API endpoint 공개 여부.
  # true  → private endpoint + Bastion 필요 + VPC Endpoints 풀셋
  # false → public endpoint (개발 중 기본값)
  eks_private_mode = false

  # VPC Endpoints 풀셋 활성화 (eks_private_mode = true 시 함께 켜야 함)
  # false → S3 Gateway VPCE만 유지
  enable_full_vpce = false

  # Hibernate 워크플로우에서 NAT GW / VPCE를 제거할지 여부
  # enable_full_vpce = false면 의미 없음
  enable_vpce = false
}
