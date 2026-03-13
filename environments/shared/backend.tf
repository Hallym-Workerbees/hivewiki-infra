terraform {
  backend "s3" {
    bucket       = "hivewiki-infra-state-bucket"
    key          = "shared/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true
    encrypt      = true
  }
}
