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
# Amazon Linux 2 AMI (guaranteed Free Tier eligible)
locals {
  # Amazon Linux 2 AMI (HVM) - Kernel 5.10, SSD Volume Type - eu-central-1
  # This is the standard Free Tier eligible AMI
  free_tier_ami = "ami-01a612f2c60d80101"
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
    echo "=== Starting user data script for Amazon Linux 2 ==="
    
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
    run_cmd yum update -y
    
    # Install Docker (universal method for Amazon Linux)
    echo "=== Installing Docker ==="
    # Try amazon-linux-extras first, fallback to direct yum install
    if command -v amazon-linux-extras >/dev/null 2>&1; then
        run_cmd amazon-linux-extras install docker -y
    else
        run_cmd yum install -y docker
    fi
    
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

# Data sources for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC for EKS cluster
resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "eks-vpc"
    "kubernetes.io/cluster/voting-app-cluster" = "shared"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "eks-igw"
  }
}

# Public subnets
resource "aws_subnet" "eks_public_subnet" {
  count             = 2
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "eks-public-subnet-${count.index + 1}"
    "kubernetes.io/cluster/voting-app-cluster" = "shared"
    "kubernetes.io/role/elb" = "1"
  }
}

# Route table for public subnets
resource "aws_route_table" "eks_public_rt" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = {
    Name = "eks-public-rt"
  }
}

# Route table association
resource "aws_route_table_association" "eks_public_rta" {
  count          = 2
  subnet_id      = aws_subnet.eks_public_subnet[count.index].id
  route_table_id = aws_route_table.eks_public_rt.id
}

# IAM role for EKS cluster
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

# Attach required policies to cluster role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# IAM role for EKS node group
resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach required policies to node role
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# EKS Cluster
resource "aws_eks_cluster" "voting_app_cluster" {
  name     = "voting-app-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.28"

  vpc_config {
    subnet_ids = aws_subnet.eks_public_subnet[*].id
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]

  tags = {
    Name = "voting-app-cluster"
  }
}

# EKS Node Group
resource "aws_eks_node_group" "voting_app_nodes" {
  cluster_name    = aws_eks_cluster.voting_app_cluster.name
  node_group_name = "voting-app-nodes"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.eks_public_subnet[*].id

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.small"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_registry_policy,
  ]

  tags = {
    Name = "voting-app-nodes"
  }
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

# EKS Cluster Outputs
output "eks_cluster_id" {
  value = aws_eks_cluster.voting_app_cluster.id
}

output "eks_cluster_arn" {
  value = aws_eks_cluster.voting_app_cluster.arn
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.voting_app_cluster.endpoint
}

output "eks_cluster_version" {
  value = aws_eks_cluster.voting_app_cluster.version
}

output "eks_node_group_arn" {
  value = aws_eks_node_group.voting_app_nodes.arn
}
