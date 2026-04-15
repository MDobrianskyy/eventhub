terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}

resource "aws_security_group" "eventhub" {
  name        = "seventhub"
  description = "Security group for eventhub"

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
    cidr_blocks = ["217.20.176.193/32"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["217.20.176.193/32"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["217.20.176.193/32"]
  }

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["217.20.176.193/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "eventhub" {
  ami                    = "ami-089146c5626baa6bf"
  instance_type          = "t3.micro"
  key_name               = "devops-key"
  vpc_security_group_ids = [aws_security_group.eventhub.id]

  tags = {
    Name = "eventhub"
    }
}
resource "aws_eip" "eventhub" {
  instance = aws_instance.eventhub.id
}

output "elastic_ip" {
  value = aws_eip.eventhub.public_ip
}

# Спочатку дізнаємось які subnets існують в дефолтному VPC
data "aws_vpc" "default" {
  default = true   # беремо саме дефолтний VPC
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]  # фільтруємо subnets по VPC
  }
}

# Потім створюємо subnet group — "ось список де можна розміщуватись"
resource "aws_db_subnet_group" "eventhub" {
  name       = "eventhub"
  subnet_ids = data.aws_subnets.default.ids  # передаємо всі три subnets
}

resource "aws_security_group" "rds" {
  name        = "eventhub-rds"
  description = "Allow PostgreSQL from EC2 only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eventhub.id]  # ← тільки від EC2 SG
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "redis" {
  name        = "eventhub-redis"
  description = "Allow Redis from EC2 only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.eventhub.id]  # ← тільки від EC2 SG
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elasticache_subnet_group" "eventhub" {
  name       = "eventhub-echache-sg"
  subnet_ids = data.aws_subnets.default.ids  # передаємо всі три subnets
}

resource "aws_db_instance" "eventhub" {
  identifier        = "eventhub"        # ім'я інстансу в AWS консолі
  engine            = "postgres"        # який движок БД (mysql, postgres, etc.)
  engine_version    = "15"             # версія PostgreSQL
  instance_class    = "db.t3.micro"    # розмір машини (як instance_type для EC2)
  allocated_storage = 10               # розмір диску в GB (Free Tier дає 20GB)

  db_name  = "eventhub"    # назва бази яка створюється автоматично
  username = "eventhub"    # логін адміністратора БД
  password = "changeme123" # пароль (потім замінимо на secrets)

  db_subnet_group_name   = aws_db_subnet_group.eventhub.name        # де може жити (subnet group яку ми вже написали)
  vpc_security_group_ids = [aws_security_group.rds.id]              # який SG застосувати (rds, не eventhub!)

  skip_final_snapshot = true  # при destroy не робити backup — для навчання ок
}

resource "aws_elasticache_cluster" "eventhub" {
  cluster_id           = "eventhub"          # ім'я кластеру в AWS консолі
  engine               = "redis"             # redis або memcached
  node_type            = "cache.t3.micro"    # розмір ноди (аналог instance_type)
  num_cache_nodes      = 1                   # кількість нод (Free Tier — 1)
  parameter_group_name = "default.redis7"    # конфігурація Redis (дефолтна для версії 7)
  port                 = 6379               # стандартний порт Redis

  subnet_group_name  = aws_elasticache_subnet_group.eventhub.name  # де може жити
  security_group_ids = [aws_security_group.redis.id]               # який SG застосувати
}
