provider "aws" {
  region = "ap-northeast-2"
  default_tags {
    tags = {
      Environment = "dev"
      Project     = "Hivewiki"
      ManagedBy   = "OpenTofu"
    }
  }
}
