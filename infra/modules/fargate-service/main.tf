data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  # If no real image is supplied, use a public placeholder. The service will
  # come up but won't serve /api endpoints — push a real backend image to
  # ECR and re-apply (or update the service with the new task def revision).
  effective_image = var.container_image != "" ? var.container_image : "public.ecr.aws/nginx/nginx:stable"
}

# -----------------------------------------------------------------------------
# ECS cluster
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name = "${var.name_prefix}-cluster"
  }
}

resource "aws_cloudwatch_log_group" "tasks" {
  name              = "/ecs/${var.name_prefix}-api"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "/ecs/${var.name_prefix}-api"
  }
}

# -----------------------------------------------------------------------------
# IAM: task execution role (used by ECS agent: pull image, write logs, read secrets)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "task_execution" {
  name = "${var.name_prefix}-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.name_prefix}-task-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow the execution role to read the secrets we inject as task env vars.
resource "aws_iam_role_policy" "task_execution_secrets" {
  count = length(var.secret_arns_to_read) > 0 ? 1 : 0

  name = "read-task-secrets"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "ssm:GetParameters"
      ]
      Resource = concat(var.secret_arns_to_read, var.ssm_parameter_arns_to_read)
    }]
  })
}

# -----------------------------------------------------------------------------
# IAM: task role (used by the application code itself)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "task" {
  name = "${var.name_prefix}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.name_prefix}-task-role"
  }
}

# App reads SSM parameters (published infra outputs) and secrets at runtime.
resource "aws_iam_role_policy" "task_app" {
  count = length(var.secret_arns_to_read) + length(var.ssm_parameter_arns_to_read) > 0 ? 1 : 0

  name = "app-runtime-reads"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.secret_arns_to_read
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = var.ssm_parameter_arns_to_read
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# ALB
# -----------------------------------------------------------------------------
resource "aws_lb" "this" {
  name               = "${var.name_prefix}-api-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "${var.name_prefix}-api-alb"
  }
}

resource "aws_lb_target_group" "this" {
  name        = "${var.name_prefix}-api-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  tags = {
    Name = "${var.name_prefix}-api-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# -----------------------------------------------------------------------------
# ECS task definition + service
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "api"
    image     = local.effective_image
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.tasks.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "api"
      }
    }

    # App reads further config from SSM/Secrets at startup via the task role.
    environment = [
      { name = "ENVIRONMENT", value = "phase0" },
      { name = "AWS_REGION", value = data.aws_region.current.name }
    ]
  }])

  tags = {
    Name = "${var.name_prefix}-api"
  }
}

resource "aws_ecs_service" "this" {
  name            = "${var.name_prefix}-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.fargate_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "api"
    container_port   = var.container_port
  }

  # Fast bring-up: skip the grace period delay.
  health_check_grace_period_seconds = 60

  tags = {
    Name = "${var.name_prefix}-api"
  }

  depends_on = [aws_lb_listener.http]

  lifecycle {
    # Allow tasks to be replaced by re-deploys without forcing a service replacement.
    ignore_changes = [desired_count]
  }
}
