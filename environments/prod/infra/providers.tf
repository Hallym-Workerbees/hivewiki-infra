provider "aws" {
  region = "ap-northeast-2"
  default_tags {
    tags = {
      Environment = "prod"
      Project     = "Hivewiki"
      ManagedBy   = "OpenTofu"
    }
  }
}
