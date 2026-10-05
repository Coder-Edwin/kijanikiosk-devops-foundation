output "servers" {
  description = "Everything pipeline.sh needs per server, as JSON: public/private IP and the app port Terraform opened."
  value = {
    for name, s in module.app_server : name => {
      public_ip  = s.public_ip
      private_ip = s.private_ip
      app_port   = s.app_port
    }
  }
}

output "api_server_ip" {
  description = "Public IP of the api server."
  value       = module.app_server["api"].public_ip
}

output "payments_server_ip" {
  description = "Public IP of the payments server."
  value       = module.app_server["payments"].public_ip
}

output "logs_server_ip" {
  description = "Public IP of the logs server."
  value       = module.app_server["logs"].public_ip
}

output "ssh_commands" {
  description = "Copy-paste SSH command for each server."
  value = {
    for name, s in module.app_server :
    name => "ssh -i ${trimsuffix(var.ssh_public_key_path, ".pub")} ubuntu@${s.public_ip}"
  }
}

output "ansible_inventory_lines" {
  description = "Host lines in the exact format of ansible/inventory.ini, for manual copy if pipeline.sh is not used."
  value = join("\n", [
    for name, s in module.app_server :
    "${name} ansible_host=${s.public_ip} private_ip=${s.private_ip} tf_app_port=${s.app_port}"
  ])
}

output "vpc_cidr" {
  description = "CIDR of the VPC the servers live in. Ansible uses it for firewall and systemd IP allow-lists."
  value       = local.vpc_cidr
}

output "ami_id" {
  description = "The Ubuntu 22.04 AMI the lookup resolved to (for the record)."
  value       = data.aws_ami.ubuntu.id
}
