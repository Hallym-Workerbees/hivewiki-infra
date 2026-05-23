module "loki_chunk_bucket" {
  source      = "../../s3-archive"
  bucket_name = "${var.cluster_name}-loki-chunk"
  bucket_lifecycle_rules = {
    daily = {
      enabled         = true
      id              = "daily-backup-retention"
      prefix          = ""
      transitions     = [{ days = 30, storage_class = "STANDARD_IA" }]
      expiration_days = 90
    }
  }
}

module "loki_ruler_bucket" {
  source      = "../../s3-archive"
  bucket_name = "${var.cluster_name}-loki-ruler"
}

module "log_archive_bucket" {
  source      = "../../s3-archive"
  bucket_name = "${var.cluster_name}-log-archive"
  bucket_lifecycle_rules = {
    daily = {
      enabled = true
      id      = "daily-backup-retention"
      prefix  = ""
      transitions = [
        { days = 30, storage_class = "STANDARD_IA" },
        { days = 90, storage_class = "DEEP_ARCHIVE" },
      ]
    }
  }
}
