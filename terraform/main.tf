terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "region"          { default = "eu-west-1" }
variable "instance_type"   { default = "t3.large" }
variable "public_key_path" { default = "~/.ssh/id_ed25519.pub" }
variable "my_ip_cidr" {
  description = "Your public IP as a /32, for example 203.0.113.7/32"
  type        = string
}

provider "aws" {
  region = var.region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "k3s" {
  key_name   = "capstone-k3s"
  public_key = file(pathexpand(var.public_key_path))
}

resource "aws_security_group" "k3s" {
  name        = "capstone-k3s"
  description = "k3s single node cluster"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from me"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }
  ingress {
    description = "Kubernetes API from me"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }
  ingress {
    description = "Voting app NodePorts"
    from_port   = 31000
    to_port     = 31001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "k3s" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.k3s.key_name
  vpc_security_group_ids      = [aws_security_group.k3s.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 30
  }

  user_data = <<-EOF
    #!/bin/bash
    TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 120")
    IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--tls-san $IP" sh -
  EOF

  tags = {
    Name = "capstone-k3s"
  }
}

output "public_ip" {
  value = aws_instance.k3s.public_ip
}