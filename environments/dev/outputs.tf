output "runner_ssh_command" {
  description = "Command to SSH into the private runner"
  value       = module.runner.ssh_command
}

output "artifact_registry_url" {
  description = "The URL for the Docker Artifact Registry"
  value       = module.artifact_registry.repo_url
}