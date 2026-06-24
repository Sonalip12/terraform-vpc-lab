provider "aws" {
  region = var.region
}

#################################################
# VPC
#################################################

resource "aws_vpc" "custom_vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "custom-vpc"
  }
}

#################################################
# PUBLIC SUBNET
#################################################

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "ap-southeast-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

#################################################
# PRIVATE SUBNET
#################################################

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.custom_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "ap-southeast-2b"

  tags = {
    Name = "private-subnet"
  }
}

#################################################
# INTERNET GATEWAY
#################################################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.custom_vpc.id

  tags = {
    Name = "custom-igw"
  }
}

#################################################
# ELASTIC IP FOR NAT
#################################################

resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

#################################################
# NAT GATEWAY
#################################################

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  depends_on = [
    aws_internet_gateway.igw
  ]

  tags = {
    Name = "nat-gateway"
  }
}

#################################################
# PUBLIC ROUTE TABLE
#################################################

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.custom_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

#################################################
# PRIVATE ROUTE TABLE
#################################################

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.custom_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private-route-table"
  }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

#################################################
# FRONTEND SECURITY GROUP
#################################################

resource "aws_security_group" "frontend_sg" {
  name        = "frontend-sg"
  description = "Frontend Security Group"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    description = "HTTP"

    from_port = 80
    to_port   = 80
    protocol  = "tcp"

    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"

    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "frontend-sg"
  }
}

#################################################
# BACKEND SECURITY GROUP
#################################################

resource "aws_security_group" "backend_sg" {
  name        = "backend-sg"
  description = "Backend Security Group"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    description = "MongoDB from Frontend"

    from_port = 27017
    to_port   = 27017
    protocol  = "tcp"

    security_groups = [
      aws_security_group.frontend_sg.id
    ]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "backend-sg"
  }
}

#################################################
# AMAZON LINUX ARM64 AMI
#################################################

data "aws_ami" "amazon_linux" {

  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-6.1-arm64"]
  }
}

#################################################
# FRONTEND EC2
#################################################

resource "aws_instance" "frontend" {

  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  subnet_id = aws_subnet.public_subnet.id

  associate_public_ip_address = true

  key_name = var.key_name

  vpc_security_group_ids = [
    aws_security_group.frontend_sg.id
  ]

  user_data = <<-EOF
#!/bin/bash
yum update -y
yum install -y httpd

systemctl start httpd
systemctl enable httpd

echo "<h1>Frontend Apache Server</h1>" > /var/www/html/index.html
EOF

  tags = {
    Name = "frontend-server"
  }
}

#################################################
# BACKEND EC2
#################################################

resource "aws_instance" "backend" {

  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  subnet_id = aws_subnet.private_subnet.id

  associate_public_ip_address = false

  key_name = var.key_name

  vpc_security_group_ids = [
    aws_security_group.backend_sg.id
  ]

  user_data = <<-EOF
#!/bin/bash

yum update -y

cat > /etc/yum.repos.d/mongodb-org.repo << EOL
[mongodb-org-6.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2/mongodb-org/6.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-6.0.asc
EOL

yum install -y mongodb-org

systemctl start mongod
systemctl enable mongod
EOF

  tags = {
    Name = "backend-server"
  }
}