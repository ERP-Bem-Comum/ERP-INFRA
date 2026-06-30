variable "mgc_api_key" {
  description = "API key da Magalu Cloud. Prefira o env MGC_API_KEY / TF_VAR_mgc_api_key (NÃO commitar)."
  type        = string
  sensitive   = true
  default     = null
}

variable "environment" {
  description = "Nome do ambiente (qa/staging/prod)."
  type        = string
}

variable "region" {
  description = "Região Magalu."
  type        = string
  default     = "br-ne1"
}

variable "availability_zone" {
  description = "Zona de disponibilidade."
  type        = string
  default     = "br-ne1-a"
}

variable "machine_type" {
  description = "Flavor da VM."
  type        = string
  default     = "BV1-2-20"
}

variable "ssh_public_key" {
  description = "Chave pública SSH para o módulo cadastrar. Use null quando ssh_key_name apontar para uma chave existente."
  type        = string
  default     = null
  nullable    = true
}

variable "ssh_key_name" {
  description = "Nome de uma chave SSH já cadastrada na Magalu Cloud."
  type        = string
  default     = null
  nullable    = true
}

variable "ssh_allowed_cidr" {
  description = "CIDR autorizado a SSH. Use o IP público do operador com /32."
  type        = string
}
