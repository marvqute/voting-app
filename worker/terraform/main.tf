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

# Use a known Free Tier eligible AMI for eu-central-1
locals {
  # Amazon Linux 2 AMI (Free Tier eligible)
  ami_id = "ami-0c02fb55956c7d316"
}

# Security group for voting app
resource "aws_security_group" "voting_app_sg" {
  name_prefix = "voting-app-sg"
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

resource "aws_instance" "voting_app" {
  ami                     = local.ami_id
  instance_type           = "t2.micro"
  key_name               = "mykeypair"
  vpc_security_group_ids = [aws_security_group.voting_app_sg.id]

  # Disable detailed monitoring to ensure Free Tier compatibility
  monitoring = false

  # Basic root volume
  root_block_device {
    volume_type = "gp2"
    volume_size = 8
    encrypted   = false
    delete_on_termination = true
  }

  # User data for application setup
  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install docker -y
    service docker start
    chkconfig docker on
    usermod -aG docker ec2-user
    
    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    # Create app directory
    mkdir -p /home/ec2-user/app
    cd /home/ec2-user/app
    
    # Download docker-compose file
    curl -o docker-compose.yaml https://raw.githubusercontent.com/marvqute/voting-app/main/docker-compose.prod.yaml
    
    # Start services
    sleep 30
    docker-compose up -d
  EOF
  )

  tags = {
    Name = "voting-app-instance"
    Environment = "production"
  }
}

output "public_ip" {
  value = aws_instance.voting_app.public_ip
  description = "Public IP address of the voting app instance"
}

output "instance_id" {
  value = aws_instance.voting_app.id
  description = "EC2 instance ID"
}

output "ami_id" {
  value = local.ami_id
  description = "AMI ID used for the instance"
}

output "vote_app_url" {
  value = "http://${aws_instance.voting_app.public_ip}:5000"
  description = "URL for the voting application"
}

output "result_app_url" {
  value = "http://${aws_instance.voting_app.public_ip}:8091"
  description = "URL for the results application"
}
