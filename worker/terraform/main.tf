terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

# Get the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Security group for voting app
resource "aws_security_group" "voting_app_sg" {
  name        = "voting-app-sg"
  description = "Security group for voting application"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # Vote app port
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Voting app"
  }

  # Result app port
  ingress {
    from_port   = 8091
    to_port     = 8091
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Results app"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "voting-app-security-group"
  }
}

# EC2 Instance
resource "aws_instance" "app" {
  ami           = data.aws_ami.amazon_linux.id  # Use latest Amazon Linux 2 AMI
  instance_type = "t2.micro"
  key_name      = "mykeypair"
  
  vpc_security_group_ids = [aws_security_group.voting_app_sg.id]
  
  tags = {
    Name = "voting-app"
  }
  
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install docker -y
    service docker start
    usermod -aG docker ec2-user
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-Linux-x86_64" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    mkdir -p /home/ec2-user/app
    cd /home/ec2-user/app
    curl -o docker-compose.yaml https://raw.githubusercontent.com/marvqute/voting-app/main/docker-compose.prod.yaml
    sleep 30
    /usr/local/bin/docker-compose up -d
  EOF
}

# Outputs
output "ami_id" {
  value = data.aws_ami.amazon_linux.id
}

output "ami_name" {
  value = data.aws_ami.amazon_linux.name
}

output "public_ip" {
  value = aws_instance.app.public_ip
}

output "instance_id" {
  value = aws_instance.app.id
}

output "vote_app_url" {
  value = "http://${aws_instance.app.public_ip}:5000"
}

output "result_app_url" {
  value = "http://${aws_instance.app.public_ip}:8091"
}
