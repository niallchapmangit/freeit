output "node" {
  description = "The provisioned node contract. Consumed by E1.2 (k3s) and downstream."
  value       = local.node
}

output "node_public_ip" {
  description = "Stable public IP of the company node."
  value       = local.node.public_ip
}

output "ssh_command" {
  description = "Ready-to-use SSH command for the node."
  value       = "ssh ${local.node.ssh_user}@${local.node.public_ip}"
}
