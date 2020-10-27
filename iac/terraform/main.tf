terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 2.70"
    }
  }
}

provider "aws" {
  profile = "default"
  region  = "us-east-1"
}


#
#   VPC 
# 
resource "aws_vpc" "custom_vpc" {

  # IP rage
  cidr_block = "10.10.0.0/16"

  # Enable auto hostname assiging
  enable_dns_hostnames = true
  tags = {
    Name = "custom_vpc"
  }
}


# public-subnet - public
resource "aws_subnet" "public-subnet" {
  depends_on = [
    aws_vpc.custom_vpc
  ]

  vpc_id = aws_vpc.custom_vpc.id

  cidr_block = "10.10.1.0/24"

  availability_zone = "us-east-1a"

  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet"
  }
}

# private-subnet - private
resource "aws_subnet" "private-subnet" {
  depends_on = [
    aws_vpc.custom_vpc,
    aws_subnet.public-subnet
  ]

  vpc_id = aws_vpc.custom_vpc.id

  cidr_block = "10.10.2.0/24"

  availability_zone = "us-east-1b"

  tags = {
    Name = "Private Subnet"
  }
}

# private subnet 2
resource "aws_subnet" "private-subnet-2" {
  depends_on = [
    aws_vpc.custom_vpc,
    aws_subnet.public-subnet
  ]

  vpc_id = aws_vpc.custom_vpc.id

  cidr_block = "10.10.3.0/24"

  availability_zone = "us-east-1c"

  tags = {
    Name = "Private Subnet 2"
  }
}

# Internet Gateway for VPC
resource "aws_internet_gateway" "internet_gateway" {
  depends_on = [
    aws_vpc.custom_vpc,
    aws_subnet.public-subnet,
    aws_subnet.private-subnet,
    aws_subnet.private-subnet-2
  ]

  vpc_id = aws_vpc.custom_vpc.id

  tags = {
    Name = "ig-public-and-private-vpc"
  }
}

resource "aws_route_table" "public-subnet-route" {
  depends_on = [
    aws_vpc.custom_vpc,
    aws_internet_gateway.internet_gateway
  ]

  vpc_id = aws_vpc.custom_vpc.id

  # NAT rule
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "route table for Internet gateway"
  }
}

resource "aws_route_table_association" "route-ig-association" {
  depends_on = [
    aws_vpc.custom_vpc,
    aws_subnet.public-subnet,
    aws_subnet.private-subnet,
    aws_route_table.public-subnet-route
  ]

  # to public subnet
  subnet_id = aws_subnet.public-subnet.id

  # Route table
  route_table_id = aws_route_table.public-subnet-route.id
}


# elastic ip
resource "aws_eip" "nat-gateway-eip" {
  depends_on = [
    aws_route_table_association.route-ig-association
  ]

  vpc = true
}

# NAT Gateway
resource "aws_nat_gateway" "nat-gateway" {
  depends_on = [
    aws_eip.nat-gateway-eip
  ]

  # allocate the eip to NAT gateway
  allocation_id = aws_eip.nat-gateway-eip.id

  # Connect it to public subnet
  subnet_id = aws_subnet.public-subnet.id

  tags = {
    Name = "NAT-Gateway"
  }
}

# Route table for NAT Gateway
resource "aws_route_table" "nat-gateway-route" {
  depends_on = [
    aws_nat_gateway.nat-gateway
  ]

  vpc_id = aws_vpc.custom_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat-gateway.id
  }

  tags = {
    Name = "route table for NAT"
  }
}

# Associate route table for nat gateway to the public subnet
resource "aws_route_table_association" "nat-gateway-route-assiciation" {
  depends_on = [
    aws_route_table.nat-gateway-route
  ]

  # add private subnet to route table to dhcp of private subnet
  subnet_id = aws_subnet.private-subnet.id

  route_table_id = aws_route_table.nat-gateway-route.id
}


#
#   Security Groups
#

resource "aws_security_group" "bastion" {
  depends_on = [
    aws_vpc.custom_vpc,
    aws_subnet.private-subnet,
    aws_subnet.public-subnet
  ]

  description = "ping, ssh"

  name = "bastion-sg"

  vpc_id = aws_vpc.custom_vpc.id

  ingress {
    description = "ping"
    from_port   = 0
    to_port     = 0
    protocol    = "ICMP"
    cidr_blocks = ["0.0.0.0/0"]

  }

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  # outbound all
  egress {
    description = "output from bastion"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "docker-host-sg" {
  depends_on = [
    aws_vpc.custom_vpc,
    aws_subnet.public-subnet,
    aws_subnet.private-subnet,
    aws_subnet.private-subnet-2,
    aws_security_group.bastion
  ]

  description = "docker-host security group"
  name        = "docker-host to bastion"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    description     = "bastion to dh"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description = "dh web - dev"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
  }

  ingress {
    description = "dh web - master"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
  }

  # outbound
  egress {
    description = "output from bastion"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}


#
# key and instances
#

resource "aws_key_pair" "key-pair" {

  key_name = var.ssh-key-name

  public_key = file(var.ssh-key-path)

}

resource "aws_instance" "bastion-host" {
  depends_on = [
    aws_security_group.bastion
  ]

  ami           = "ami-032930428bf1abbff"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public-subnet.id

  key_name = var.ssh-key-name

  vpc_security_group_ids = [aws_security_group.bastion.id]

  tags = {
    Name = "Bastion host"
  }
}

# docker host 1
resource "aws_instance" "docker-host" {
  depends_on = [
    aws_security_group.bastion,
    aws_security_group.docker-host-sg
  ]

  ami           = "ami-032930428bf1abbff"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private-subnet.id

  key_name = var.ssh-key-name

  vpc_security_group_ids = [aws_security_group.docker-host-sg.id]

  tags = {
    Name = "docker host instance"
  }
}

# docker host 2 - not DRY - need to loop over
resource "aws_instance" "docker-host-2" {
  depends_on = [
    aws_security_group.bastion,
    aws_security_group.docker-host-sg
  ]

  ami           = "ami-032930428bf1abbff"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private-subnet-2.id

  key_name = var.ssh-key-name

  vpc_security_group_ids = [aws_security_group.docker-host-sg.id]

  tags = {
    Name = "docker host instance 2"
  }
}
