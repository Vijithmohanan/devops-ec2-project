# Configure AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- 1. Dynamic AMI Lookup (Professional Practice) ---
# Finds the latest official Amazon Linux 2023 AMI in the specified region.
data "aws_ami" "latest_amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    # Adjust this pattern if you switch to a different OS (e.g., Ubuntu)
    values = ["al2023-ami-2023.*-x86_64"] 
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- 2. Networking (VPC and Subnets) ---
resource "aws_vpc" "app_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "DevOps-Cluster-VPC" }
}

resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.app_vpc.id
  cidr_block = "10.0.1.0/24"
  # This makes the EC2s and ALB publicly accessible
  map_public_ip_on_launch = true 
  # Using the first available AZ in the region
  availability_zone = "${var.aws_region}a" 
  tags = { Name = "Public-Subnet-A" }
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = "10.0.2.0/24" # Use a different CIDR block
  map_public_ip_on_launch = true
  # Crucial change: Specify a different AZ (e.g., 'b')
  availability_zone       = "${var.aws_region}b" 
  tags                    = { Name = "Public-Subnet-B" }
}

# --- 3. Security Group (Allows SSH and HTTP) ---
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.app_vpc.id
  name   = "web-access-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }
  ingress {
    from_port   = 80
    to_port     = 80
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

# --- 4. EC2 Instance Cluster (3 Servers - Free Tier) ---
resource "aws_instance" "app_servers" {
  count         = 3
  # ... other configurations ...
  key_name      = var.key_pair_name
  
  # Distribute servers across the two subnets based on the count index
  subnet_id     = element([
    aws_subnet.public_subnet.id,
    aws_subnet.public_subnet_b.id,
  ], count.index % 2) # This alternates the subnet ID (0%2=0, 1%2=1, 2%2=0...)

  vpc_security_group_ids = [aws_security_group.web_sg.id]
  tags = {
    Name = "App-Server-${count.index + 1}"
  }
}

# --- 5. Application Load Balancer (ALB) ---
resource "aws_lb" "app_lb" {
  name               = "app-lb-cluster"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_subnet.id]
}

resource "aws_lb" "app_lb" {
  name               = "app-lb-cluster"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  
  # Crucial Fix: Add both subnets from different AZs
  subnets            = [
    aws_subnet.public_subnet.id,
    aws_subnet.public_subnet_b.id
  ]
}

resource "aws_lb_target_group" "app_tg" {
  name     = "app-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.app_vpc.id
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Attach all 3 EC2 instances to the Target Group
resource "aws_lb_target_group_attachment" "app_attachments" {
  count            = 3
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.app_servers[count.index].id
  port             = 80
}

# --- 6. Outputs for Ansible and User Verification ---
output "all_instance_ips" {
  description = "Public IPs of all application servers for Ansible inventory"
  value       = [for instance in aws_instance.app_servers : instance.public_ip]
}

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer for accessing the cluster"
  value       = aws_lb.app_lb.dns_name
}