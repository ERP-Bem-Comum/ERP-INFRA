output "instance_id" {
  description = "ID da instância."
  value       = mgc_virtual_machine_instances.this.id
}

output "public_ipv4" {
  description = "IPv4 público (se alocado)."
  value       = mgc_virtual_machine_instances.this.ipv4
}

output "private_ipv4" {
  description = "IPv4 privado."
  value       = mgc_virtual_machine_instances.this.local_ipv4
}

output "ssh_key_name" {
  description = "Nome da SSH key usada."
  value       = local.ssh_key_name
}
