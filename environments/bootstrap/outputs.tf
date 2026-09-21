output "app_vpc_name" {
  description = "Name of the app-plane VPC"
  value       = module.app_network.network_name
}

output "app_private_subnet_id" {
  description = "ID of the app-plane private subnet"
  value       = module.app_network.subnet_id
}

output "app_subnet_cidr" {
  description = "CIDR of the app-plane private subnet"
  value       = module.app_network.subnet_ip_cidr_range
}

output "infra_vpc_name" {
  description = "Name of the infra-plane VPC"
  value       = module.infra_network.network_name
}

output "infra_private_subnet_id" {
  description = "ID of the infra-plane private subnet"
  value       = module.infra_network.subnet_id
}

output "infra_subnet_cidr" {
  description = "CIDR of the infra-plane private subnet (authorize on GKE master)"
  value       = module.infra_network.subnet_ip_cidr_range
}

# Backwards-compatible aliases
output "vpc_name" {
  description = "Alias for app_vpc_name"
  value       = module.app_network.network_name
}

output "private_subnet_id" {
  description = "Alias for app_private_subnet_id"
  value       = module.app_network.subnet_id
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
