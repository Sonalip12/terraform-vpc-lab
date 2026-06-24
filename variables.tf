variable "region" {
  default = "ap-southeast-2"
}

variable "instance_type" {
  default = "t4g.small"
}

variable "key_name" {
  default = "terraform-key"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  default = "10.0.2.0/24"
}