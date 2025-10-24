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

# Use a known Free Tier eligible AMI for new accounts
# Amazon Linux 2023 AMI with kernel-6.1
locals {
  # Amazon Linux 2023 AMI (HVM) - Kernel 6.1, SSD Volume Type - eu-central-1
  free_tier_ami = "ami-0e7e134863fac4946"
}

# Security group for voting app
resource "aws_security_group" "voting_app_sg" {
  name_prefix = "voting-app-sg-"
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

  lifecycle {
    create_before_destroy = true
  }
}

# EC2 Instance
resource "aws_instance" "app" {
  ami           = local.free_tier_ami
  instance_type = "t3.micro"
  key_name      = "mykeypair"
  
  vpc_security_group_ids = [aws_security_group.voting_app_sg.id]
  
  # Minimal configuration for new Free Tier accounts
  monitoring = false
  
  tags = {
    Name = "voting-app"
  }
  
  user_data = <<-EOF
    #!/bin/bash
    set -e  # Exit on any error
    
    # Log everything
    exec > >(tee /var/log/user-data.log) 2>&1
    
    echo "Starting user data script for Amazon Linux 2023..."
    
    # Update system (Amazon Linux 2023 uses dnf)
    dnf update -y
    
    # Install Docker (Amazon Linux 2023 method)
    dnf install -y docker
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Add ec2-user to docker group
    usermod -aG docker ec2-user
    
    # Install Docker Compose v2 (newer method)
    DOCKER_COMPOSE_VERSION="v2.23.0"
    curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Create symbolic link for docker-compose command
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    # Verify installations
    echo "Docker version:"
    docker --version
    echo "Docker Compose version:"
    docker-compose --version
    
    # Wait for Docker daemon to be ready
    echo "Waiting for Docker daemon..."
    until docker info >/dev/null 2>&1; do
        echo "Waiting for Docker daemon to start..."
        sleep 5
    done
    
    # Create app directory
    mkdir -p /home/ec2-user/app
    chown ec2-user:ec2-user /home/ec2-user/app
    
    # Download docker-compose file
    echo "Downloading docker-compose file..."
    curl -o /home/ec2-user/app/docker-compose.yaml https://raw.githubusercontent.com/marvqute/voting-app/main/docker-compose.prod.yaml
    chown ec2-user:ec2-user /home/ec2-user/app/docker-compose.yaml
    
    # Change to app directory and start services
    cd /home/ec2-user/app
    echo "Starting Docker containers..."
    docker-compose up -d
    
    echo "User data script completed successfully!"
  EOF
}

# Outputs
output "ami_id" {
  value = local.free_tier_ami
}

output "security_group_id" {
  value = aws_security_group.voting_app_sg.id
}

output "security_group_name" {
  value = aws_security_group.voting_app_sg.name
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
