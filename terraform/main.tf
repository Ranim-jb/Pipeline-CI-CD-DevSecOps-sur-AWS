terraform {
  required_version = ">= 1.6.0"

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

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_ecr_repository" "app" {
  name                 = var.ecr_repository
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # prototype : permet terraform destroy avec des images

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecs_cluster" "app" {
  name = "devsecops-demo"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Learner Lab : impossible de créer des rôles IAM, on utilise le rôle existant LabRole.
# (En production : rôle d'exécution dédié, voir production/oidc.tf.example)
data "aws_iam_role" "lab" {
  name = "LabRole"
}

resource "aws_security_group" "app" {
  name        = "devsecops-demo-app"
  description = "Acces reseau minimal de l API DevSecOps de demonstration"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Demo universitaire - acces HTTP a l API"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Sortie Internet pour les mises a jour et acces ECR"
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/devsecops-demo"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.logs.arn
}

resource "aws_ecs_task_definition" "app" {
  family                   = "devsecops-demo"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = data.aws_iam_role.lab.arn

  container_definitions = jsonencode([
    {
      name      = "api"
      # Image de départ : le pipeline enregistre ensuite une nouvelle révision
      # de la tâche avec le tag = SHA du commit (les tags ECR sont immuables).
      image                  = "${aws_ecr_repository.app.repository_url}:bootstrap"
      essential              = true
      readonlyRootFilesystem = true

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "api"
        }
      }

      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "devsecops-demo"
  cluster         = aws_ecs_cluster.app.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true
  }

  # Le pipeline CI/CD enregistre de nouvelles révisions de la tâche :
  # Terraform ne doit pas les écraser.
  lifecycle {
    ignore_changes = [task_definition]
  }
}
