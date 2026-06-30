variable "name" {
  description = "Nome da instância (ex.: erp-bem-comum-qa)."
  type        = string
}

variable "machine_type" {
  description = "Flavor da VM Magalu (ex.: BV1-2-10)."
  type        = string
}

variable "image" {
  description = "Imagem do SO."
  type        = string
  default     = "cloud-ubuntu-24.04 LTS"
}

variable "availability_zone" {
  description = "Zona de disponibilidade (ex.: br-ne1-a)."
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC onde a interface primária será criada."
  type        = string
}

variable "security_group_ids" {
  description = "IDs de security groups associados à interface primária na criação."
  type        = list(string)
}

variable "ssh_key_name" {
  description = "Nome de uma SSH key JÁ existente na conta. Se null, o módulo cria uma a partir de ssh_public_key."
  type        = string
  default     = null
}

variable "ssh_public_key" {
  description = "Chave pública SSH (só usada quando ssh_key_name é null, para criar a key)."
  type        = string
  default     = null
}

variable "allocate_public_ipv4" {
  description = "Cria e associa um IPv4 público."
  type        = bool
  default     = true
}

variable "cloud_init" {
  description = "Script cloud-init em texto plano (o módulo faz o base64encode). null = nenhum."
  type        = string
  default     = null
}
