# Reusable KijaniKiosk application server: one EC2 instance plus the
# security group that defines exactly who may talk to it.
# Every value comes in through a variable. Nothing is environment-specific here.

locals {
  full_name = "kijanikiosk-${var.environment}-${var.name}"
  tags = merge(var.tags, {
    Name        = local.full_name
    Project     = "kijanikiosk"
    Role        = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

resource "aws_security_group" "this" {
  name        = "${local.full_name}-sg"
  description = "KijaniKiosk ${var.name} server: SSH from operator, app port from allowed sources"
  vpc_id      = var.vpc_id
  tags        = local.tags
}

# One rule resource per source CIDR (rather than inline blocks) so rule order
# can never produce a spurious diff on the second plan.
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.ssh_allowed_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "SSH for Ansible, operator IP only"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
  tags              = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "app" {
  for_each = toset(var.app_allowed_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "KijaniKiosk ${var.name} service"
  ip_protocol       = "tcp"
  from_port         = var.app_port
  to_port           = var.app_port
  cidr_ipv4         = each.value
  tags              = local.tags
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "Outbound for package installs and OS updates"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags              = local.tags
}

resource "aws_instance" "this" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = true

  # IMDSv2 only: blocks the classic SSRF trick of reading instance
  # credentials from the metadata service with a plain GET.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true
    tags                  = local.tags
  }

  tags = local.tags

  lifecycle {
    # The AMI comes from a "most recent Ubuntu 22.04" lookup. When Canonical
    # publishes a new image, a plain plan would want to replace every server.
    # Ignoring it keeps the second run at zero changes; rebuilding onto a new
    # image becomes a deliberate act (terraform apply -replace=...).
    ignore_changes = [ami]
  }
}
