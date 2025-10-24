provider "aws" {
  region = "eu-central-1"
}

# Data source to find the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
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
  ami                    = data.aws_ami.amazon_linux.id  # Use latest Amazon Linux 2023 AMI
  instance_type          = "t2.micro"                     # Free Tier eligible
  key_name              = "mykeypair" 
  vpc_security_group_ids = [aws_security_group.voting_app_sg.id]

  # Enable detailed monitoring (optional, helps with troubleshooting)
  monitoring = false

  # Root volume configuration (Free Tier allows up to 30GB)
  root_block_device {
    volume_type = "gp2"
    volume_size = 30  # Minimum required size for Amazon Linux 2023
    encrypted   = false
  }

  user_data = <<-EOF
              #!/bin/bash
              # Update system
              sudo dnf update -y
              
              # Install Docker
              sudo dnf install -y docker
              sudo systemctl start docker
              sudo systemctl enable docker
              sudo usermod -aG docker ec2-user
              
              # Install Docker Compose
              sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              sudo chmod +x /usr/local/bin/docker-compose
              sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
              
              # Create working directory
              mkdir -p /home/ec2-user/app
              cd /home/ec2-user/app
              
              # Download production docker-compose file
              curl -o docker-compose.yaml https://raw.githubusercontent.com/marvqute/voting-app/main/docker-compose.prod.yaml
              
              # Wait for Docker to be ready and start applications
              sleep 30
              /usr/local/bin/docker-compose up -d
              EOF

  tags = {
    Name = "voting-app-instance"
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
  value = data.aws_ami.amazon_linux.id
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
