output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "Public IPv4 address Ansible connects to."
  value       = aws_instance.this.public_ip
}

output "private_ip" {
  description = "Private IPv4 address inside the VPC."
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "ID of the server's security group."
  value       = aws_security_group.this.id
}

output "app_port" {
  description = "Port the service listens on (echoed so Ansible can check it agrees)."
  value       = var.app_port
}
