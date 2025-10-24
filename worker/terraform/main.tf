provider "aws" {
  region = "eu-central-1"
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
  ami                    = "ami-0592c673f0b1e7665" # Amazon Linux 2023 AMI (eu-central-1)
  instance_type          = "t2.micro"
  key_name              = "mykeypair" # Updated to match your actual key name
  vpc_security_group_ids = [aws_security_group.voting_app_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo dnf update -y
              sudo dnf install -y docker
              sudo systemctl start docker
              sudo systemctl enable docker
              sudo usermod -aG docker ec2-user
              sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              sudo chmod +x /usr/local/bin/docker-compose
              sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
              cd /home/ec2-user
              git clone https://github.com/marvqute/voting-app.git
              cd voting-app
              docker-compose -f docker-compose.prod.yaml up -d
              EOF

  tags = {
    Name = "voting-app-instance"
  }
}

output "public_ip" {
  value = aws_instance.voting_app.public_ip
  description = "Public IP address of the voting app instance"
}

output "vote_app_url" {
  value = "http://${aws_instance.voting_app.public_ip}:5000"
  description = "URL for the voting application"
}

output "result_app_url" {
  value = "http://${aws_instance.voting_app.public_ip}:8091"
  description = "URL for the results application"
}
