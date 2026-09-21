output "infra_vpc_name" {
  description = "Name of the infra-plane VPC"
  value       = module.infra_network.network_name
}

output "infra_vpc_self_link" {
  description = "Self-link of the infra-plane VPC (for env peering)"
  value       = module.infra_network.network_self_link
}

output "infra_private_subnet_id" {
  description = "ID of the infra-plane private subnet"
  value       = module.infra_network.subnet_id
}

output "infra_subnet_cidr" {
  description = "CIDR of the infra-plane private subnet (authorize on GKE master)"
  value       = module.infra_network.subnet_ip_cidr_range
}

output "runner_name" {
  description = "The name of the infra Runner VM"
  value       = module.runner.runner_instance_name
}

output "runner_zone" {
  description = "The zone where the Runner is located"
  value       = module.runner.runner_instance_zone
}

output "runner_ssh_command" {
  description = "IAP SSH command for the infra runner (register with labels self-hosted,infra,{env})"
  value       = module.runner.ssh_command
}

output "runner_registration_labels" {
  description = "GitHub Actions labels to use when registering this runner"
  value       = "self-hosted,infra,${var.env}"
}

output "node_sa_email" {
  description = "GKE node service account email (created by bootstrap-iam)"
  value       = module.bootstrap_iam.node_sa_email
}

output "app_sa_email" {
  description = "Application service account email (created by bootstrap-iam)"
  value       = module.bootstrap_iam.app_sa_email
}

output "app_runner_sa_email" {
  description = "ARC app-runner service account email (created by bootstrap-iam)"
  value       = module.bootstrap_iam.app_runner_sa_email
}

output "external_secrets_sa_email" {
  description = "External Secrets service account email (created by bootstrap-iam)"
  value       = module.bootstrap_iam.external_secrets_sa_email
}
