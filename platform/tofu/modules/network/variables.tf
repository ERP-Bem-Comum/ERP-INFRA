variable "name_prefix" {
  description = "Prefixo dos recursos do ambiente (ex.: erp-bem-comum-qa)."
  type        = string
}

variable "vpc_description" {
  description = "Descrição da VPC."
  type        = string
  default     = "VPC do ERP Bem Comum"
}

variable "ssh_allowed_cidr" {
  description = "CIDR autorizado a SSH (22). Use o IP administrativo com /32."
  type        = string
}

variable "http_allowed_cidr" {
  description = "CIDR autorizado a HTTP/HTTPS (80/443). A borda Caddy serve a app."
  type        = string
  default     = "0.0.0.0/0"
}
