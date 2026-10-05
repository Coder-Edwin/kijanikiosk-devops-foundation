variable "aws_region" {
  description = "AWS region for the staging servers. ap-south-1 is the region used in class; af-south-1 is the production target but needs account opt-in."
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment label used in names and tags."
  type        = string
  default     = "staging"
}

variable "instance_type" {
  description = "EC2 instance size for all three servers. t3.micro is free-tier eligible."
  type        = string
  default     = "t3.micro"
}

variable "ssh_key_name" {
  description = "Name given to the EC2 key pair. Ansible uses the matching private key (group_vars/kijanikiosk.yml: ssh_private_key_path)."
  type        = string
  default     = "kijanikiosk-staging"
}

variable "ssh_public_key_path" {
  description = "Path to the public half of the SSH key Ansible uses. pipeline.sh derives it from ssh_private_key_path in group_vars so the two cannot drift."
  type        = string
}

variable "admin_cidr" {
  description = "The operator's public IP as a /32. Only this address may SSH in. pipeline.sh detects it automatically."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "ubuntu_ami_name_filter" {
  description = "Name pattern for the Ubuntu image lookup. Ubuntu 22.04 (jammy) to match the Week 3 baseline."
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

variable "ubuntu_ami_owner" {
  description = "AWS account that publishes the official Ubuntu images (Canonical)."
  type        = string
  default     = "099720109477"
}

variable "root_volume_size_gb" {
  description = "Root volume size for each server, in GiB."
  type        = number
  default     = 10
}

variable "servers" {
  description = "The servers to create, keyed by role. app_port must agree with service_port in the matching Ansible host_vars file; the playbook asserts this. public_app opens app_port to admin_cidr as well as the VPC."
  type = map(object({
    app_port   = number
    public_app = bool
  }))
  default = {
    api = {
      app_port   = 8080
      public_app = true
    }
    payments = {
      app_port   = 8081
      public_app = false
    }
    logs = {
      app_port   = 8082
      public_app = false
    }
  }
}
