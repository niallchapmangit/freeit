terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  # Portable size enum → AWS instance type
  instance_type_map = {
    small  = "t3.micro"   # 2 vCPU / 1 GiB  — NOT suitable for k3s
    medium = "t3.medium"  # 2 vCPU / 4 GiB  — k3s floor
    large  = "t3.large"   # 2 vCPU / 8 GiB
  }

  instance_type = local.instance_type_map[var.node_size]

  common_tags = merge(var.tags, {
    Project   = "freeit"
    CompanyId = var.company_id
    ManagedBy = "opentofu"
  })
}

# Latest Ubuntu 24.04 LTS in the target region
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "company" {
  key_name   = "freeit-${var.company_id}"
  public_key = var.ssh_public_key
  tags       = local.common_tags
}

resource "aws_vpc" "company" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.common_tags, { Name = "freeit-${var.company_id}" })
}

resource "aws_internet_gateway" "company" {
  vpc_id = aws_vpc.company.id
  tags   = merge(local.common_tags, { Name = "freeit-${var.company_id}" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.company.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = false # We use an EIP instead
  tags                    = merge(local.common_tags, { Name = "freeit-${var.company_id}-public" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.company.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.company.id
  }

  tags = merge(local.common_tags, { Name = "freeit-${var.company_id}-public" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "company" {
  name        = "freeit-${var.company_id}"
  description = "freeit company node: SSH + k3s API (restricted) + public ports"
  vpc_id      = aws_vpc.company.id
  tags        = merge(local.common_tags, { Name = "freeit-${var.company_id}" })
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.ssh_cidrs)

  security_group_id = aws_security_group.company.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
  description       = "SSH"
}

resource "aws_vpc_security_group_ingress_rule" "k3s_api" {
  for_each = toset(var.api_cidrs)

  security_group_id = aws_security_group.company.id
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
  description       = "k3s API"
}

resource "aws_vpc_security_group_ingress_rule" "public" {
  for_each = toset([for p in var.public_ports : tostring(p)])

  security_group_id = aws_security_group.company.id
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Public port ${each.value}"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.company.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow all egress"
}

resource "aws_instance" "node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = local.instance_type
  key_name               = aws_key_pair.company.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.company.id]
  user_data              = var.cloud_init
  user_data_replace_on_change = false # cloud-init runs once on first boot

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 40
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  tags = merge(local.common_tags, { Name = "freeit-${var.company_id}" })
}

resource "aws_eip" "node" {
  domain   = "vpc"
  instance = aws_instance.node.id
  tags     = merge(local.common_tags, { Name = "freeit-${var.company_id}" })

  depends_on = [aws_internet_gateway.company]
}
