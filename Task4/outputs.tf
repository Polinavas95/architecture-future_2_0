output "app_vm_ip" {
  description = "Public IP of the application VM"
  value       = yandex_compute_instance.app.network_interface[0].nat_ip_address
}

output "db_host" {
  description = "PostgreSQL cluster host (FQDN)"
  value       = yandex_mdb_postgresql_cluster.main.host[0].fqdn
}

output "db_name" {
  description = "Database name"
  value       = yandex_mdb_postgresql_database.app.name
}

output "db_user" {
  description = "Database user"
  value       = yandex_mdb_postgresql_user.app.name
  sensitive   = true
}

output "security_group_id" {
  description = "Security group ID"
  value       = yandex_vpc_security_group.main.id
}