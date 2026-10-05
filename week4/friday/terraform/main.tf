# No provider default_tags: combined with per-volume tags they are a known
# source of perpetual diffs, which would break the zero-change second run.
# Tags are set explicitly in the module instead.
provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Lookups: nothing environment-specific is typed into a resource block.
# ---------------------------------------------------------------------------

# Latest official Ubuntu 22.04 image in whichever region we are in.
# Replaces the hardcoded "ami-01a00762f46d584a1" from Tuesday's class code,
# which only exists in one region and goes stale.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = [var.ubuntu_ami_owner]

  filter {
    name   = "name"
    values = [var.ubuntu_ami_name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  # sort() makes the choice deterministic, so a second plan picks the same subnet.
  subnet_id = sort(data.aws_subnets.default.ids)[0]
  vpc_cidr  = data.aws_vpc.default.cidr_block
}

# ---------------------------------------------------------------------------
# One key pair shared by the three servers. The private half never leaves the
# operator's machine; only the public key is uploaded.
# ---------------------------------------------------------------------------
resource "aws_key_pair" "ansible" {
  key_name   = var.ssh_key_name
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = {
    Project     = "kijanikiosk"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Three servers from one module call.
# ---------------------------------------------------------------------------
module "app_server" {
  source   = "./modules/app_server"
  for_each = var.servers

  name                = each.key
  environment         = var.environment
  ami_id              = data.aws_ami.ubuntu.id
  instance_type       = var.instance_type
  key_name            = aws_key_pair.ansible.key_name
  subnet_id           = local.subnet_id
  vpc_id              = data.aws_vpc.default.id
  ssh_allowed_cidrs   = [var.admin_cidr]
  app_port            = each.value.app_port
  app_allowed_cidrs   = each.value.public_app ? [local.vpc_cidr, var.admin_cidr] : [local.vpc_cidr]
  root_volume_size_gb = var.root_volume_size_gb
}
