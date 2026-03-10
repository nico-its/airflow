provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_vpc_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  lower   = true
  numeric = true
  special = false
}

locals {
  subnet_id = data.aws_subnets.default_vpc_subnets.ids[0]
  owner_login = split("@", var.owner)[0]

  instance_name = "airflow-training-${local.owner_login}-${random_string.suffix.result}"

  common_tags = {
    owner    = var.owner
    entity   = "unimate"
    ephemere = "oui"
  }
}

resource "aws_security_group" "airflow_sg" {
  name        = "airflow-training-sg"
  description = "Security group for training Airflow EC2"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH open to all for training"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Airflow UI open to all for training"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "airflow-training-sg-${random_string.suffix.result}"
  })
}

resource "aws_iam_role" "ec2_ssm_role" {
  name = "airflow-training-ec2-ssm-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "airflow-training-ec2-profile-${random_string.suffix.result}"
  role = aws_iam_role.ec2_ssm_role.name

  tags = local.common_tags
}

resource "aws_instance" "airflow" {
  for_each = toset(var.instance_names)

  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.airflow_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  associate_public_ip_address = true

  user_data = templatefile("${path.module}/airflow.sh", {
    INSTANCE_NAME          = local.instance_name
    AIRFLOW_VERSION        = var.airflow_version
    AIRFLOW_ADMIN_USER     = var.airflow_admin_user
    AIRFLOW_ADMIN_PASSWORD = var.airflow_admin_password
    AIRFLOW_ADMIN_EMAIL    = var.owner
  })

  root_block_device {
    volume_size = var.disk_size
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name      = each.value
    Role      = "airflow-training"
    ManagedBy = "terraform"
  })

  volume_tags = merge(local.common_tags, {
    Name      = "${each.value}-root-volume"
    Role      = "airflow-training"
    ManagedBy = "terraform"
  })
}