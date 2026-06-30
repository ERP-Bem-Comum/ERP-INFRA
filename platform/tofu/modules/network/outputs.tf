output "vpc_id" {
  description = "ID da VPC."
  value       = mgc_network_vpcs.this.id
}

output "security_group_id" {
  description = "ID do security group."
  value       = mgc_network_security_groups.this.id
}
