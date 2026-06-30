# State remoto no Object Storage da Magalu (S3-compatível) — obrigatório (platform/README §3).
# Credenciais via env: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY = key-pair do Object Storage
# (NÃO inline aqui). O bucket precisa existir ANTES do init (ver README › Bootstrap do state).
terraform {
  backend "s3" {
    bucket = "erp-bem-comum-tfstate"
    key    = "qa/terraform.tfstate"
    region = "br-ne1"

    endpoints = {
      s3 = "https://br-ne1.magaluobjects.com/"
    }

    # Magalu é S3-compatível, não AWS: pular as validações específicas da AWS.
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
