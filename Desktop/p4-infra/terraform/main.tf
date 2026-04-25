terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment after creating your S3 bucket + DynamoDB lock table
  # backend "s3" {
  #   bucket         = "securechat-tf-state"
  #   key            = "prod/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "securechat-tf-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ── VPC ───────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.common_tags, { Name = "${var.project_name}-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${var.project_name}-igw" })
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "${var.project_name}-public-${count.index + 1}" })
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = merge(local.common_tags, { Name = "${var.project_name}-private-${count.index + 1}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── KMS ───────────────────────────────────────────────────────────────────────
# Used to encrypt all application secrets (DB_URL, JWT_SECRET, etc.)

resource "aws_kms_key" "secrets" {
  description             = "${var.project_name} secrets encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = merge(local.common_tags, { Name = "${var.project_name}-kms-key" })
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.project_name}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# ── IAM Role for EC2 (SSM + KMS + CloudWatch) ─────────────────────────────────

resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "ec2_kms" {
  name = "${var.project_name}-ec2-kms-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowKMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.secrets.arn
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.app.arn}:*"
      },
      {
        Sid    = "AllowSSMParameterRead"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.project_name}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ── EC2 ───────────────────────────────────────────────────────────────────────

resource "aws_instance" "app" {
  ami                    = var.ec2_ami
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = var.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    kms_key_id            = aws_kms_key.secrets.arn
    delete_on_termination = true
  }

  user_data = file("${path.module}/../scripts/ec2-setup.sh")

  tags = merge(local.common_tags, { Name = "${var.project_name}-app-server" })
}

resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"
  tags     = merge(local.common_tags, { Name = "${var.project_name}-eip" })
}

# ── RDS MySQL ─────────────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags       = merge(local.common_tags, { Name = "${var.project_name}-db-subnet-group" })
}

resource "aws_db_instance" "mysql" {
  identifier             = "${var.project_name}-db"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.secrets.arn
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = false
  final_snapshot_identifier = "${var.project_name}-final-snapshot"
  backup_retention_period = 7
  deletion_protection    = true
  publicly_accessible    = false
  multi_az               = false # set true for prod HA

  tags = merge(local.common_tags, { Name = "${var.project_name}-mysql" })
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "app" {
  name              = "/securechat/app"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.secrets.arn
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "nginx" {
  name              = "/securechat/nginx"
  retention_in_days = 14
  tags              = local.common_tags
}

# ── SSM Parameter Store (KMS-encrypted secrets) ───────────────────────────────
# Values are placeholders — set real values after provisioning.

resource "aws_ssm_parameter" "jwt_secret" {
  name   = "/${var.project_name}/JWT_SECRET"
  type   = "SecureString"
  value  = "REPLACE_ME_BEFORE_DEPLOY"
  key_id = aws_kms_key.secrets.key_id
  tags   = local.common_tags
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "db_host" {
  name   = "/${var.project_name}/DB_HOST"
  type   = "SecureString"
  value  = aws_db_instance.mysql.address
  key_id = aws_kms_key.secrets.key_id
  tags   = local.common_tags
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "db_name" {
  name   = "/${var.project_name}/DB_NAME"
  type   = "SecureString"
  value  = var.db_name
  key_id = aws_kms_key.secrets.key_id
  tags   = local.common_tags
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "db_user" {
  name   = "/${var.project_name}/DB_USER"
  type   = "SecureString"
  value  = var.db_username
  key_id = aws_kms_key.secrets.key_id
  tags   = local.common_tags
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "db_pass" {
  name   = "/${var.project_name}/DB_PASS"
  type   = "SecureString"
  value  = "REPLACE_ME_BEFORE_DEPLOY"
  key_id = aws_kms_key.secrets.key_id
  tags   = local.common_tags
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "kms_key_id" {
  name   = "/${var.project_name}/KMS_KEY_ID"
  type   = "SecureString"
  value  = aws_kms_key.secrets.key_id
  key_id = aws_kms_key.secrets.key_id
  tags   = local.common_tags
  lifecycle { ignore_changes = [value] }
}
