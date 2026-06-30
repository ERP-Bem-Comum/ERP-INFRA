# VPC isolada do ambiente.
resource "mgc_network_vpcs" "this" {
  name        = "${var.name_prefix}-vpc"
  description = var.vpc_description
}

# Security group (firewall) do ambiente. Remove as regras default e declara
# explicitamente SSH + HTTP + HTTPS no ingress e IPv4 no egress.
resource "mgc_network_security_groups" "this" {
  name                  = "${var.name_prefix}-sg"
  description           = "SG do ${var.name_prefix}: SSH + HTTP + HTTPS"
  disable_default_rules = true
}

locals {
  ingress_rules = {
    ssh   = { port = 22, cidr = var.ssh_allowed_cidr, desc = "SSH" }
    http  = { port = 80, cidr = var.http_allowed_cidr, desc = "HTTP (Caddy -> redirect HTTPS)" }
    https = { port = 443, cidr = var.http_allowed_cidr, desc = "HTTPS (app)" }
  }
}

resource "mgc_network_security_groups_rules" "ingress" {
  for_each = local.ingress_rules

  description       = each.value.desc
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = each.value.cidr
  security_group_id = mgc_network_security_groups.this.id
}

# A Magalu Cloud exige egress para a VM concluir o boot e acessar registries,
# updates e APIs externas. O ingress continua restrito às regras acima.
resource "mgc_network_security_groups_rules" "egress_ipv4" {
  description       = "Egress IPv4"
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = mgc_network_security_groups.this.id
}
