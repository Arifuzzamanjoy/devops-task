output "instance_id" {
  description = "Contabo instance id"
  value       = contabo_instance.app.id
}

output "public_ip" {
  description = "Public IPv4 of the server"
  value       = contabo_instance.app.ip_config[0].v4[0].ip
}

output "health_url" {
  description = "Health endpoint used by the CD smoke test"
  value       = "http://${contabo_instance.app.ip_config[0].v4[0].ip}:${var.app_port}/health"
}

output "ssh_command" {
  description = "SSH as the deploy user"
  value       = "ssh ${var.deploy_user}@${contabo_instance.app.ip_config[0].v4[0].ip}"
}

output "grafana_tunnel" {
  description = "Grafana is bound to localhost on the server; reach it through a tunnel"
  value       = "ssh -N -L 3000:127.0.0.1:3000 ${var.deploy_user}@${contabo_instance.app.ip_config[0].v4[0].ip}"
}
