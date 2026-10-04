###############################################################################
# AI ROBOT - COMPLETE AWS FOUNDATION
# Single Terraform file
#
# Architecture:
#
# Internet
#    |
#    v
#   ALB
#    |
#    v
# ECS / EC2 / EKS
#    |
#    +---- AI Agent
#    +---- Browser Worker
#    +---- Code Worker
#    +---- PDF Worker
#    +---- Skill Worker
#    |
#    +---- S3          -> Documents / Books / Knowledge / Workspace
#    +---- DynamoDB    -> Tasks / Memory / State / Metadata
#    +---- RDS        -> Relational application data (optional)
#    +---- Vector DB  -> Semantic memory (application-managed)
#    +---- CloudWatch -> Logs / Monitoring
#
# IMPORTANT:
# Heavy/cost-generating compute is disabled by default.
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

###############################################################################
# VARIABLES
###############################################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "ai-robot"
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_ec2" {
  description = "Create EC2 AI Robot compute"
  type        = bool
  default     = false
}

variable "enable_ecs" {
  description = "Create ECS cluster"
  type        = bool
  default     = false
}

variable "enable_rds" {
  description = "Create RDS database"
  type        = bool
  default     = false
}

variable "enable_eks" {
  description = "Create EKS cluster"
  type        = bool
  default     = false
}

variable "enable_alb" {
  description = "Create Application Load Balancer"
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = "Create NAT Gateway"
  type        = bool
  default     = false
}

variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "airobot"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "airobotadmin"
}

variable "db_password" {
  description = "Database password"
  type        = string
  default     = "CHANGE_ME"
  sensitive   = true
}

###############################################################################
# PROVIDER
###############################################################################

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Application = "AI-Robot"
    }
  }
}

###############################################################################
# DATA
###############################################################################

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

###############################################################################
# LOCALS
###############################################################################

locals {
  name = "${var.project_name}-${var.environment}"

  az1 = data.aws_availability_zones.available.names[0]
  az2 = data.aws_availability_zones.available.names[1]

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

###############################################################################
# VPC
###############################################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

###############################################################################
# INTERNET GATEWAY
###############################################################################

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name}-igw"
  }
}

###############################################################################
# PUBLIC SUBNET 1
###############################################################################

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = local.az1
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-1"
    Tier = "public"
  }
}

###############################################################################
# PUBLIC SUBNET 2
###############################################################################

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = local.az2
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-2"
    Tier = "public"
  }
}

###############################################################################
# PRIVATE SUBNET 1
###############################################################################

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = local.az1

  tags = {
    Name = "${local.name}-private-1"
    Tier = "private"
  }
}

###############################################################################
# PRIVATE SUBNET 2
###############################################################################

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = local.az2

  tags = {
    Name = "${local.name}-private-2"
    Tier = "private"
  }
}

###############################################################################
# PUBLIC ROUTE TABLE
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name}-public-rt"
  }
}

###############################################################################
# PUBLIC ROUTE ASSOCIATIONS
###############################################################################

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

###############################################################################
# NAT GATEWAY
###############################################################################

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "${local.name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public_1.id

  depends_on = [
    aws_internet_gateway.main
  ]

  tags = {
    Name = "${local.name}-nat"
  }
}

###############################################################################
# PRIVATE ROUTE TABLE
###############################################################################

resource "aws_route_table" "private" {
  count  = var.enable_nat_gateway ? 1 : 0
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[0].id
  }

  tags = {
    Name = "${local.name}-private-rt"
  }
}

resource "aws_route_table_association" "private_1" {
  count = var.enable_nat_gateway ? 1 : 0

  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private[0].id
}

resource "aws_route_table_association" "private_2" {
  count = var.enable_nat_gateway ? 1 : 0

  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private[0].id
}

###############################################################################
# SECURITY GROUP - ALB
###############################################################################

resource "aws_security_group" "alb" {
  count = var.enable_alb ? 1 : 0

  name        = "${local.name}-alb-sg"
  description = "Security group for AI Robot ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-alb-sg"
  }
}

###############################################################################
# SECURITY GROUP - APP
###############################################################################

resource "aws_security_group" "app" {
  name        = "${local.name}-app-sg"
  description = "AI Robot application security group"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.enable_alb ? [1] : []

    content {
      description     = "Application traffic from ALB"
      from_port       = 8000
      to_port         = 8000
      protocol        = "tcp"
      security_groups = [aws_security_group.alb[0].id]
    }
  }

  ingress {
    description = "AI Robot API"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "Outbound internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-app-sg"
  }
}

###############################################################################
# SECURITY GROUP - DATABASE
###############################################################################

resource "aws_security_group" "database" {
  count = var.enable_rds ? 1 : 0

  name        = "${local.name}-database-sg"
  description = "AI Robot RDS security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from application"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "Outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-database-sg"
  }
}

###############################################################################
# S3 - MAIN AI ROBOT DATA BUCKET
###############################################################################

resource "aws_s3_bucket" "robot_data" {
  bucket = "${local.name}-${data.aws_caller_identity.current.account_id}"

  force_destroy = false

  tags = {
    Name = "${local.name}-data"
    Type = "AI-Robot-Storage"
  }
}

###############################################################################
# S3 VERSIONING
###############################################################################

resource "aws_s3_bucket_versioning" "robot_data" {
  bucket = aws_s3_bucket.robot_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

###############################################################################
# S3 ENCRYPTION
###############################################################################

resource "aws_s3_bucket_server_side_encryption_configuration" "robot_data" {
  bucket = aws_s3_bucket.robot_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

###############################################################################
# S3 PUBLIC ACCESS BLOCK
###############################################################################

resource "aws_s3_bucket_public_access_block" "robot_data" {
  bucket = aws_s3_bucket.robot_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

###############################################################################
# S3 DIRECTORY STRUCTURE
###############################################################################

resource "aws_s3_object" "folders" {
  for_each = toset([
    "documents/",
    "documents/books/",
    "documents/pdfs/",
    "documents/research/",
    "knowledge/",
    "knowledge/raw/",
    "knowledge/extracted/",
    "knowledge/summaries/",
    "memory/",
    "memory/conversations/",
    "memory/experiences/",
    "skills/",
    "skills/generated/",
    "skills/tested/",
    "skills/versions/",
    "workspace/",
    "workspace/uploads/",
    "workspace/outputs/",
    "backups/",
    "logs/"
  ])

  bucket  = aws_s3_bucket.robot_data.id
  key     = each.value
  content = ""
}

###############################################################################
# DYNAMODB - TASKS
###############################################################################

resource "aws_dynamodb_table" "tasks" {
  name         = "${local.name}-tasks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "task_id"

  attribute {
    name = "task_id"
    type = "S"
  }

  tags = {
    Name = "${local.name}-tasks"
  }
}

###############################################################################
# DYNAMODB - MEMORY
###############################################################################

resource "aws_dynamodb_table" "memory" {
  name         = "${local.name}-memory"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "memory_id"

  attribute {
    name = "memory_id"
    type = "S"
  }

  tags = {
    Name = "${local.name}-memory"
  }
}

###############################################################################
# DYNAMODB - AGENT STATE
###############################################################################

resource "aws_dynamodb_table" "agent_state" {
  name         = "${local.name}-agent-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "state_id"

  attribute {
    name = "state_id"
    type = "S"
  }

  tags = {
    Name = "${local.name}-agent-state"
  }
}

###############################################################################
# DYNAMODB - SKILLS
###############################################################################

resource "aws_dynamodb_table" "skills" {
  name         = "${local.name}-skills"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "skill_id"

  attribute {
    name = "skill_id"
    type = "S"
  }

  tags = {
    Name = "${local.name}-skills"
  }
}

###############################################################################
# DYNAMODB - KNOWLEDGE METADATA
###############################################################################

resource "aws_dynamodb_table" "knowledge" {
  name         = "${local.name}-knowledge"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "knowledge_id"

  attribute {
    name = "knowledge_id"
    type = "S"
  }

  tags = {
    Name = "${local.name}-knowledge"
  }
}

###############################################################################
# ECR - AI ROBOT IMAGES
###############################################################################

resource "aws_ecr_repository" "agent" {
  name                 = "${local.name}-agent"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${local.name}-agent"
  }
}

resource "aws_ecr_repository" "dashboard" {
  name                 = "${local.name}-dashboard"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${local.name}-dashboard"
  }
}

resource "aws_ecr_repository" "browser_worker" {
  name                 = "${local.name}-browser-worker"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${local.name}-browser-worker"
  }
}

resource "aws_ecr_repository" "code_worker" {
  name                 = "${local.name}-code-worker"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${local.name}-code-worker"
  }
}

resource "aws_ecr_repository" "document_worker" {
  name                 = "${local.name}-document-worker"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${local.name}-document-worker"
  }
}

resource "aws_ecr_repository" "skill_worker" {
  name                 = "${local.name}-skill-worker"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${local.name}-skill-worker"
  }
}

###############################################################################
# IAM - EC2 ROLE
###############################################################################

resource "aws_iam_role" "ec2_role" {
  count = var.enable_ec2 ? 1 : 0

  name = "${local.name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

###############################################################################
# IAM - EC2 POLICY
###############################################################################

resource "aws_iam_role_policy" "ec2_policy" {
  count = var.enable_ec2 ? 1 : 0

  name = "${local.name}-ec2-policy"
  role = aws_iam_role.ec2_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]

        Resource = [
          aws_s3_bucket.robot_data.arn,
          "${aws_s3_bucket.robot_data.arn}/*"
        ]
      },

      {
        Effect = "Allow"

        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]

        Resource = [
          aws_dynamodb_table.tasks.arn,
          aws_dynamodb_table.memory.arn,
          aws_dynamodb_table.agent_state.arn,
          aws_dynamodb_table.skills.arn,
          aws_dynamodb_table.knowledge.arn
        ]
      }
    ]
  })
}

###############################################################################
# IAM INSTANCE PROFILE
###############################################################################

resource "aws_iam_instance_profile" "ec2_profile" {
  count = var.enable_ec2 ? 1 : 0

  name = "${local.name}-ec2-profile"
  role = aws_iam_role.ec2_role[0].name
}

###############################################################################
# EC2 INSTANCE
###############################################################################

resource "aws_instance" "agent" {
  count = var.enable_ec2 ? 1 : 0

  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.ec2_instance_type

  subnet_id = aws_subnet.public_1.id

  vpc_security_group_ids = [
    aws_security_group.app.id
  ]

  iam_instance_profile = aws_iam_instance_profile.ec2_profile[0].name

  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash

              dnf update -y

              dnf install -y docker git python3

              systemctl enable docker
              systemctl start docker

              usermod -aG docker ec2-user

              mkdir -p /opt/ai-robot

              echo "AI Robot server initialized" > /opt/ai-robot/status.txt
              EOF

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${local.name}-agent"
    Role = "AI-Agent"
  }
}

###############################################################################
# ECS CLUSTER
###############################################################################

resource "aws_ecs_cluster" "main" {
  count = var.enable_ecs ? 1 : 0

  name = "${local.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${local.name}-ecs"
  }
}

###############################################################################
# ECS LOG GROUP
###############################################################################

resource "aws_cloudwatch_log_group" "ecs" {
  count = var.enable_ecs ? 1 : 0

  name              = "/ai-robot/${local.name}/ecs"
  retention_in_days = 7

  tags = {
    Name = "${local.name}-ecs-logs"
  }
}

###############################################################################
# ECS IAM TASK ROLE
###############################################################################

resource "aws_iam_role" "ecs_task_role" {
  count = var.enable_ecs ? 1 : 0

  name = "${local.name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

###############################################################################
# ECS TASK POLICY
###############################################################################

resource "aws_iam_role_policy" "ecs_task_policy" {
  count = var.enable_ecs ? 1 : 0

  name = "${local.name}-ecs-task-policy"
  role = aws_iam_role.ecs_task_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]

        Resource = [
          aws_s3_bucket.robot_data.arn,
          "${aws_s3_bucket.robot_data.arn}/*"
        ]
      },

      {
        Effect = "Allow"

        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]

        Resource = [
          aws_dynamodb_table.tasks.arn,
          aws_dynamodb_table.memory.arn,
          aws_dynamodb_table.agent_state.arn,
          aws_dynamodb_table.skills.arn,
          aws_dynamodb_table.knowledge.arn
        ]
      }
    ]
  })
}

###############################################################################
# ECS EXECUTION ROLE
###############################################################################

resource "aws_iam_role" "ecs_execution_role" {
  count = var.enable_ecs ? 1 : 0

  name = "${local.name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  count = var.enable_ecs ? 1 : 0

  role       = aws_iam_role.ecs_execution_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

###############################################################################
# ECS TASK DEFINITION
###############################################################################

resource "aws_ecs_task_definition" "agent" {
  count = var.enable_ecs ? 1 : 0

  family                   = "${local.name}-agent"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = "512"
  memory = "1024"

  execution_role_arn = aws_iam_role.ecs_execution_role[0].arn
  task_role_arn      = aws_iam_role.ecs_task_role[0].arn

  container_definitions = jsonencode([
    {
      name      = "agent"
      image     = "${aws_ecr_repository.agent.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },

        {
          name  = "S3_BUCKET"
          value = aws_s3_bucket.robot_data.bucket
        },

        {
          name  = "TASK_TABLE"
          value = aws_dynamodb_table.tasks.name
        },

        {
          name  = "MEMORY_TABLE"
          value = aws_dynamodb_table.memory.name
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"

        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs[0].name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "agent"
        }
      }
    }
  ])
}

###############################################################################
# ECS SERVICE
###############################################################################

resource "aws_ecs_service" "agent" {
  count = var.enable_ecs ? 1 : 0

  name            = "${local.name}-agent"
  cluster         = aws_ecs_cluster.main[0].id
  task_definition = aws_ecs_task_definition.agent[0].arn

  desired_count = 0

  launch_type = "FARGATE"

  network_configuration {
    subnets = [
      aws_subnet.public_1.id,
      aws_subnet.public_2.id
    ]

    security_groups = [
      aws_security_group.app.id
    ]

    assign_public_ip = true
  }
}

###############################################################################
# APPLICATION LOAD BALANCER
###############################################################################

resource "aws_lb" "main" {
  count = var.enable_alb ? 1 : 0

  name               = substr("${local.name}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb[0].id
  ]

  subnets = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]

  tags = {
    Name = "${local.name}-alb"
  }
}

###############################################################################
# ALB TARGET GROUP
###############################################################################

resource "aws_lb_target_group" "agent" {
  count = var.enable_alb ? 1 : 0

  name        = substr("${local.name}-tg", 0, 32)
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"

  vpc_id = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${local.name}-tg"
  }
}

###############################################################################
# ALB LISTENER
###############################################################################

resource "aws_lb_listener" "http" {
  count = var.enable_alb ? 1 : 0

  load_balancer_arn = aws_lb.main[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agent[0].arn
  }
}

###############################################################################
# RDS SUBNET GROUP
###############################################################################

resource "aws_db_subnet_group" "main" {
  count = var.enable_rds ? 1 : 0

  name = "${local.name}-db-subnet-group"

  subnet_ids = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id
  ]

  tags = {
    Name = "${local.name}-db-subnet-group"
  }
}

###############################################################################
# RDS MYSQL
###############################################################################

resource "aws_db_instance" "main" {
  count = var.enable_rds ? 1 : 0

  identifier = "${local.name}-mysql"

  engine         = "mysql"
  engine_version = "8.0"

  instance_class = var.rds_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name = aws_db_subnet_group.main[0].name

  vpc_security_group_ids = [
    aws_security_group.database[0].id
  ]

  publicly_accessible = false

  multi_az = false

  backup_retention_period = 0

  deletion_protection = false

  skip_final_snapshot = true

  tags = {
    Name = "${local.name}-mysql"
  }
}

###############################################################################
# EKS IAM ROLE
###############################################################################

resource "aws_iam_role" "eks_cluster" {
  count = var.enable_eks ? 1 : 0

  name = "${local.name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "eks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  count = var.enable_eks ? 1 : 0

  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

###############################################################################
# EKS CLUSTER
###############################################################################

resource "aws_eks_cluster" "main" {
  count = var.enable_eks ? 1 : 0

  name     = "${local.name}-eks"
  role_arn = aws_iam_role.eks_cluster[0].arn

  vpc_config {
    subnet_ids = [
      aws_subnet.public_1.id,
      aws_subnet.public_2.id
    ]

    endpoint_public_access = true

    endpoint_private_access = true
  }

  tags = {
    Name = "${local.name}-eks"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

###############################################################################
# CLOUDWATCH LOG GROUP
###############################################################################

resource "aws_cloudwatch_log_group" "robot" {
  name              = "/ai-robot/${local.name}"
  retention_in_days = 7

  tags = {
    Name = "${local.name}-logs"
  }
}

###############################################################################
# IAM ROLE FOR FUTURE LAMBDA / AUTOMATION
###############################################################################

resource "aws_iam_role" "automation" {
  name = "${local.name}-automation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "ecs-tasks.amazonaws.com"
          ]
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

###############################################################################
# AUTOMATION POLICY
###############################################################################

resource "aws_iam_role_policy" "automation" {
  name = "${local.name}-automation-policy"
  role = aws_iam_role.automation.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]

        Resource = [
          aws_s3_bucket.robot_data.arn,
          "${aws_s3_bucket.robot_data.arn}/*"
        ]
      },

      {
        Effect = "Allow"

        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query"
        ]

        Resource = [
          aws_dynamodb_table.tasks.arn,
          aws_dynamodb_table.memory.arn,
          aws_dynamodb_table.agent_state.arn,
          aws_dynamodb_table.skills.arn,
          aws_dynamodb_table.knowledge.arn
        ]
      },

      {
        Effect = "Allow"

        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]

        Resource = "*"
      }
    ]
  })
}

###############################################################################
# OUTPUTS
###############################################################################

output "aws_region" {
  value = var.aws_region
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_1" {
  value = aws_subnet.public_1.id
}

output "public_subnet_2" {
  value = aws_subnet.public_2.id
}

output "private_subnet_1" {
  value = aws_subnet.private_1.id
}

output "private_subnet_2" {
  value = aws_subnet.private_2.id
}

output "s3_bucket" {
  value = aws_s3_bucket.robot_data.bucket
}

output "tasks_table" {
  value = aws_dynamodb_table.tasks.name
}

output "memory_table" {
  value = aws_dynamodb_table.memory.name
}

output "agent_state_table" {
  value = aws_dynamodb_table.agent_state.name
}

output "skills_table" {
  value = aws_dynamodb_table.skills.name
}

output "knowledge_table" {
  value = aws_dynamodb_table.knowledge.name
}

output "agent_ecr" {
  value = aws_ecr_repository.agent.repository_url
}

output "dashboard_ecr" {
  value = aws_ecr_repository.dashboard.repository_url
}

output "browser_worker_ecr" {
  value = aws_ecr_repository.browser_worker.repository_url
}

output "code_worker_ecr" {
  value = aws_ecr_repository.code_worker.repository_url
}

output "document_worker_ecr" {
  value = aws_ecr_repository.document_worker.repository_url
}

output "skill_worker_ecr" {
  value = aws_ecr_repository.skill_worker.repository_url
}

output "ec2_public_ip" {
  value = var.enable_ec2 ? aws_instance.agent[0].public_ip : null
}

output "alb_dns_name" {
  value = var.enable_alb ? aws_lb.main[0].dns_name : null
}

output "rds_endpoint" {
  value = var.enable_rds ? aws_db_instance.main[0].address : null
}

output "eks_endpoint" {
  value = var.enable_eks ? aws_eks_cluster.main[0].endpoint : null
}
terraform {
  backend "s3" {
    bucket       = "ai-robot-terraform-state-279867550478"
    key          = "ai-robot/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
