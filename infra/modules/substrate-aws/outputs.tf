output "node" {
  description = "Node contract — consumed by node-bootstrap and stacks/company."
  value = {
    public_ip   = aws_eip.node.public_ip
    ssh_host    = aws_eip.node.public_ip
    ssh_user    = "ubuntu"
    instance_id = aws_instance.node.id
    region      = var.region
  }
}
