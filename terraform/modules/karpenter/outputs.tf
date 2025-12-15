output "karpenter_node_role_arn" {
  description = "ARN of the Karpenter node IAM role"
  value       = module.karpenter.node_iam_role_arn
}

output "karpenter_node_instance_profile_name" {
  description = "Name of the Karpenter node instance profile"
  value       = module.karpenter.instance_profile_name
}

output "karpenter_controller_role_arn" {
  description = "ARN of the Karpenter controller IAM role"
  value       = module.karpenter.iam_role_arn
}

output "karpenter_interruption_queue_name" {
  description = "Name of the Karpenter interruption SQS queue"
  value       = module.karpenter.queue_name
}

output "karpenter_interruption_queue_arn" {
  description = "ARN of the Karpenter interruption SQS queue"
  value       = module.karpenter.queue_arn
}
