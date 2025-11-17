output "runner_ssh_command" {
  description = "Command to SSH into the private runner"
  value       = module.runner.ssh_command
}