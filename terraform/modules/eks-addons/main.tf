resource "aws_eks_addon" "eks_addon" {
  for_each                    = { for addon in var.addon_list : addon.name => addon }
  cluster_name                = var.cluster_name
  addon_name                  = each.value.name
  addon_version               = lookup(each.value, "version", null)
  resolve_conflicts_on_update = lookup(each.value, "resolve_conflicts", "OVERWRITE")

  tags = merge(
    var.resource_tag,
    {
      Name        = "${var.cluster_name}-${each.value.name}-addon"
      Environment = var.environment
    }
  )
}
