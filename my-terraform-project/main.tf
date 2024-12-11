terraform {
  backend "s3" {
    bucket         = "custom-terraform-state-bucket-123456-bc58dc18" # Replace with your S3 bucket name
    key            = "aws-project/terraform.tfstate"                # Location of the state file in the bucket
    region         = "us-east-1"                                    # AWS region
    dynamodb_table = "custom-terraform-state-locks-123456"          # Replace with your DynamoDB table name
    encrypt        = true                                           # Enables encryption for the state file
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Random ID for Bucket Suffix
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# VPC Creation
resource "aws_vpc" "tp_cloud_devops_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "tp_cloud_devops_vpc"
  }
}

# Subnets
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.tp_cloud_devops_vpc.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = var.availability_zone_1
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.tp_cloud_devops_vpc.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = var.availability_zone_2
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet2"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main_gateway" {
  vpc_id = aws_vpc.tp_cloud_devops_vpc.id
  tags = {
    Name = "MainInternetGateway"
  }
}

# Route Table and Associations
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.tp_cloud_devops_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_gateway.id
  }

  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table_association" "public_rta1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_rta2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

# SSH Key Generation
resource "tls_private_key" "example_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "deployer_key" {
  key_name   = var.ssh_key_name
  public_key = tls_private_key.example_ssh_key.public_key_openssh
}

resource "aws_s3_bucket_object" "private_key_object" {
  bucket                 = "custom-terraform-state-bucket-123456-bc58dc18"
  key                    = "${var.ssh_key_name}.pem"
  content                = tls_private_key.example_ssh_key.private_key_pem
  acl                    = "private"
  server_side_encryption = "AES256"
}

# Security Groups
resource "aws_security_group" "web_sg" {
  name        = "web-server-sg"
  vpc_id      = aws_vpc.tp_cloud_devops_vpc.id
  description = "Security group for web server and SSH access"
}

resource "aws_security_group_rule" "allow_web_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.web_sg.id
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_web_ssh_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.web_sg.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.web_sg.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# EC2 Instance
resource "aws_instance" "public_instance" {
  ami                    = var.ec2_ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet_1.id
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    echo "<h1>Hello, World</h1>" > index.html
    python3 -m http.server 8080 & 
    EOF

  tags = {
    Name = "PublicInstance"
  }
}

# RDS Database
resource "aws_db_subnet_group" "mydb_subnet_group" {
  name       = "mydb_subnet_group"
  subnet_ids = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  tags = {
    Name = "mydb_subnet_group"
  }
}

resource "aws_db_instance" "mydb" {
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0.35"
  instance_class         = "db.t3.micro"
  identifier             = "mydb"
  username               = "dbuser"
  password               = "DBpassword2024"
  db_subnet_group_name   = aws_db_subnet_group.mydb_subnet_group.name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  publicly_accessible    = true
  multi_az               = false
  skip_final_snapshot    = true
  tags = {
    Name = "enis_tp"
  }
}

# Allow inbound RDS traffic (e.g., MySQL on port 3306)
resource "aws_security_group_rule" "allow_rds_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.web_sg.id
  from_port        = 3306 # Change this to match your database port
  to_port          = 3306 # Same as above
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"] # For production, replace this with a specific IP or CIDR block
}

# Allow inbound to backend on port 8000
resource "aws_security_group_rule" "allow_backend_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.web_sg.id
  from_port        = 8000
  to_port          = 8000 # Same as above
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"] # For production, replace this with a specific IP or CIDR block
}

# Allow inbound HTTP traffic on port 81 to access the final application
resource "aws_security_group_rule" "allow_web_http_inbound_81" {
  type              = "ingress"
  security_group_id = aws_security_group.web_sg.id
  from_port        = 81
  to_port          = 81
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
}
