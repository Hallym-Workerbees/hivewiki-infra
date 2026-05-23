module "log_archiving" {
  source        = "../../log_archiving"
  firehose_name = "${var.cluster_name}-log-archive"
  bucket_arn    = var.log_archive_bucket_arn

  log_groups = merge(
    {
      eks_api = {
        subscription_filter_name = "${var.cluster_name}-eks-api-archive"
        log_group_name           = var.eks_log_group_name
      }
    },
    var.dev_rds_log_group_name != "" ? {
      rds_postgresql = {
        subscription_filter_name = "hivewiki-dev-rds-postgresql-archive"
        log_group_name           = var.dev_rds_log_group_name
      }
    } : {},
    var.prod_rds_log_group_name != "" ? {
      prod_rds_postgresql = {
        subscription_filter_name = "hivewiki-prod-rds-postgresql-archive"
        log_group_name           = var.prod_rds_log_group_name
      }
    } : {}
  )
}
