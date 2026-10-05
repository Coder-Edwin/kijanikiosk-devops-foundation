variable "name" {
  description = "Short role name of the server (api, payments, logs). Used in the Name tag and resource names."
  type        = string
}

variable "environment" {
  description = "Environment label applied to every resource (e.g. staging)."
  type        = string
}

variable "ami_id" {
  description = "AMI to boot. Supplied by the root module's aws_ami data source; never hardcoded."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance size for this server."
  type        = string
}

variable "key_name" {
  description = "Name of the EC2 key pair whose public key is installed for the ubuntu user."
  type        = string
}

variable "subnet_id" {
  description = "Subnet the instance is launched into."
  type        = string
}

variable "vpc_id" {
  description = "VPC the server's security group belongs to."
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to reach port 22. Should be the operator's /32, never 0.0.0.0/0."
  type        = list(string)

  validation {
    condition     = !contains(var.ssh_allowed_cidrs, "0.0.0.0/0")
    error_message = "SSH must not be open to the whole internet. Pass the operator's /32."
  }
}

variable "app_port" {
  description = "TCP port the server's KijaniKiosk service listens on."
  type        = number
}

variable "app_allowed_cidrs" {
  description = "CIDR blocks allowed to reach app_port."
  type        = list(string)
}

variable "root_volume_size_gb" {
  description = "Size of the encrypted root volume in GiB."
  type        = number
}

variable "tags" {
  description = "Extra tags merged onto every resource the module creates."
  type        = map(string)
  default     = {}
}
