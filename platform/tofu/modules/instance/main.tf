# Cria a SSH key só quando um nome de key existente NÃO é informado.
resource "mgc_ssh_keys" "this" {
  count = var.ssh_key_name == null ? 1 : 0
  name  = "${var.name}-key"
  key   = var.ssh_public_key
}

locals {
  ssh_key_name = var.ssh_key_name != null ? var.ssh_key_name : mgc_ssh_keys.this[0].name
}

resource "mgc_virtual_machine_instances" "this" {
  name              = var.name
  machine_type      = var.machine_type
  image             = var.image
  availability_zone = var.availability_zone
  ssh_key_name      = local.ssh_key_name

  vpc_id                   = var.vpc_id
  creation_security_groups = var.security_group_ids
  allocate_public_ipv4     = var.allocate_public_ipv4

  user_data = var.cloud_init != null ? base64encode(var.cloud_init) : null

  lifecycle {
    precondition {
      condition     = var.ssh_key_name != null || var.ssh_public_key != null
      error_message = "Informe ssh_key_name (key existente) OU ssh_public_key (para o módulo criar a key)."
    }
  }
}
