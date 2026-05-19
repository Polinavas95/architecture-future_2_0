# main.tf
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
      version = "~> 0.110"
    }
  }
}

provider "yandex" {
  token     = var.token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.zone
}

# VPC и сеть
resource "yandex_vpc_network" "main" {
  name = "${var.project_name}-${var.environment}-network"
}

resource "yandex_vpc_subnet" "public" {
  name           = "${var.project_name}-${var.environment}-public-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["10.0.1.0/24"]
}

resource "yandex_vpc_subnet" "private" {
  name           = "${var.project_name}-${var.environment}-private-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["10.0.2.0/24"]
}

# NAT Gateway
resource "yandex_vpc_gateway" "nat" {
  name = "${var.project_name}-${var.environment}-nat-gateway"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "private" {
  name       = "${var.project_name}-${var.environment}-private-route-table"
  network_id = yandex_vpc_network.main.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat.id
  }
}

# Группа безопасности
resource "yandex_vpc_security_group" "main" {
  name        = "${var.project_name}-${var.environment}-sg"
  description = "Security group for app and DB"
  network_id  = yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    description    = "SSH"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  ingress {
    protocol       = "TCP"
    description    = "HTTP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "HTTPS"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  ingress {
    protocol       = "TCP"
    description    = "PostgreSQL from app subnet"
    v4_cidr_blocks = ["10.0.1.0/24"]
    port           = 5432
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

# Сервисный аккаунт
resource "yandex_iam_service_account" "sa" {
  name = "${var.project_name}-${var.environment}-sa"
}

# Дополнительный диск для данных
resource "yandex_compute_disk" "data" {
  name     = "${var.project_name}-${var.environment}-app-data"
  type     = "network-ssd"
  size     = 100
  zone     = var.zone
}

# Виртуальная машина (исправлен image_id)
resource "yandex_compute_instance" "app" {
  name        = "${var.project_name}-${var.environment}-app"
  platform_id = "standard-v3"
  zone        = var.zone

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = var.vm_image_id  # теперь используем переменную
      size     = 20
      type     = "network-hdd"
    }
  }

  secondary_disk {
    disk_id = yandex_compute_disk.data.id
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.main.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  service_account_id = yandex_iam_service_account.sa.id
}

# Управляемая БД PostgreSQL
resource "yandex_mdb_postgresql_cluster" "main" {
  name        = "${var.project_name}-${var.environment}-db"
  environment = var.environment == "prod" ? "PRODUCTION" : "PRESTABLE"
  network_id  = yandex_vpc_network.main.id

  config {
    version = 15
    resources {
      resource_preset_id = "s2.micro"
      disk_size          = 50
      disk_type_id       = "network-ssd"
    }
  }

  host {
    zone      = var.zone
    subnet_id = yandex_vpc_subnet.private.id
    assign_public_ip = false
  }

  security_group_ids = [yandex_vpc_security_group.main.id]
}

# Сначала создаём пользователя
resource "yandex_mdb_postgresql_user" "app" {
  cluster_id = yandex_mdb_postgresql_cluster.main.id
  name       = "app_user"
  password   = var.db_password
  grants     = ["mdb_admin"]  # изменено с "ALL" на "mdb_admin"
}

# Потом создаём БД, указывая владельцем созданного пользователя
resource "yandex_mdb_postgresql_database" "app" {
  cluster_id = yandex_mdb_postgresql_cluster.main.id
  name       = "clinic_db"
  owner      = yandex_mdb_postgresql_user.app.name
}