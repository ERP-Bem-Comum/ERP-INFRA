output "instance_id" {
  description = "ID da VM."
  value       = module.instance.instance_id
}

output "public_ipv4" {
  description = "IPv4 público da VM."
  value       = module.instance.public_ipv4
}

output "private_ipv4" {
  description = "IPv4 privado da VM."
  value       = module.instance.private_ipv4
}

output "vpc_id" {
  description = "ID da VPC."
  value       = module.network.vpc_id
}
