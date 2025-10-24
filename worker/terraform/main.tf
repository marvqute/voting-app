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
    
    # Comprehensive logging
    exec > >(tee /var/log/user-data.log) 2>&1
    date
    echo "=== Starting user data script for Amazon Linux 2023 ==="
    
    # Function to log and run commands
    run_cmd() {
        echo "Running: $*"
        "$@"
        local exit_code=$?
        echo "Exit code: $exit_code"
        return $exit_code
    }
    
    # Update system
    echo "=== Updating system ==="
    run_cmd dnf update -y
    
    # Install Docker
    echo "=== Installing Docker ==="
    run_cmd dnf install -y docker
    
    # Start Docker service
    echo "=== Starting Docker service ==="
    run_cmd systemctl start docker
    run_cmd systemctl enable docker
    
    # Add ec2-user to docker group
    echo "=== Adding ec2-user to docker group ==="
    run_cmd usermod -aG docker ec2-user
    
    # Install Docker Compose
    echo "=== Installing Docker Compose ==="
    DOCKER_COMPOSE_VERSION="v2.23.0"
    run_cmd curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
    run_cmd chmod +x /usr/local/bin/docker-compose
    
    # Create symlinks
    echo "=== Creating Docker Compose symlinks ==="
    run_cmd ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    # Add to PATH for all users
    echo 'export PATH=$PATH:/usr/local/bin' >> /etc/profile
    
    # Wait for Docker to be ready
    echo "=== Waiting for Docker daemon ==="
    for i in {1..30}; do
        if docker info >/dev/null 2>&1; then
            echo "Docker daemon is ready!"
            break
        fi
        echo "Waiting for Docker daemon... attempt $i/30"
        sleep 10
    done
    
    # Verify installations
    echo "=== Verifying installations ==="
    docker --version || echo "Docker version check failed"
    /usr/local/bin/docker-compose --version || echo "Docker Compose version check failed"
    
    # Create app directory and download compose file
    echo "=== Setting up application ==="
    run_cmd mkdir -p /home/ec2-user/app
    run_cmd chown ec2-user:ec2-user /home/ec2-user/app
    
    echo "=== Downloading docker-compose file ==="
    run_cmd curl -o /home/ec2-user/app/docker-compose.yaml https://raw.githubusercontent.com/marvqute/voting-app/main/docker-compose.prod.yaml
    run_cmd chown ec2-user:ec2-user /home/ec2-user/app/docker-compose.yaml
    
    # Create a startup script for manual execution
    cat > /home/ec2-user/start-app.sh << 'SCRIPT'
#!/bin/bash
export PATH=$PATH:/usr/local/bin
cd /home/ec2-user/app
echo "Starting Docker containers..."
docker-compose down || true
docker-compose pull
docker-compose up -d
echo "Application started!"
docker-compose ps
SCRIPT
    
    run_cmd chmod +x /home/ec2-user/start-app.sh
    run_cmd chown ec2-user:ec2-user /home/ec2-user/start-app.sh
    
    echo "=== User data script completed ==="
    date
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
