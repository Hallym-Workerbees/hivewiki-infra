resource "aws_vpc_endpoint" "this" {
  for_each = var.endpoints

  vpc_id            = var.vpc_id
  service_name      = each.value.service_name
  vpc_endpoint_type = each.value.endpoint_type

  private_dns_enabled = each.value.endpoint_type == "Interface" ? try(each.value.private_dns_enabled, true) : null
  subnet_ids          = each.value.endpoint_type == "Interface" ? try(each.value.subnet_ids, null) : null
  security_group_ids  = each.value.endpoint_type == "Interface" ? try(each.value.security_group_ids, null) : null
  route_table_ids     = each.value.endpoint_type == "Gateway" ? try(each.value.route_table_ids, null) : null

  policy          = try(each.value.policy, null)
  ip_address_type = try(each.value.ip_address_type, null)

  tags = merge(
    var.tags,
    try(each.value.tags, {}),
    {
      Name = each.key
    }
  )
}
