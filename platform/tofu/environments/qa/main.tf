locals {
  name_prefix = "erp-bem-comum-${var.environment}"
}

module "network" {
  source = "../../modules/network"

  name_prefix      = local.name_prefix
  ssh_allowed_cidr = var.ssh_allowed_cidr
}

module "instance" {
  source = "../../modules/instance"

  name                 = local.name_prefix
  machine_type         = var.machine_type
  availability_zone    = var.availability_zone
  vpc_id               = module.network.vpc_id
  security_group_ids   = [module.network.security_group_id]
  ssh_key_name         = var.ssh_key_name
  ssh_public_key       = var.ssh_public_key
  allocate_public_ipv4 = true
  cloud_init           = file("${path.module}/cloud-init.yaml")
}
