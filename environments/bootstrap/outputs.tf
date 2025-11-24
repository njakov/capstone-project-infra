output "vpc_name" {
  description = "The name of the VPC created."
  value       = module.network.network_name
}

output "private_subnet_id" {
  description = "The ID of the private subnet created."
  value       = module.network.subnet_id
}

output "runner_name" {
  description = "The name of the Runner VM."
  value       = module.runner.runner_instance_name
}

output "runner_zone" {
  description = "The zone where the Runner is located."
  value       = module.runner.runner_instance_zone
}

output "runner_ssh_command" {
  description = "Copy/Paste this command to connect to your runner!"
  value       = module.runner.ssh_command
}