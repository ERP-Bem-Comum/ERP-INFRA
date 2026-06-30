# A api_key vem do env MGC_API_KEY (ou TF_VAR_mgc_api_key). NUNCA commitar a chave.
provider "mgc" {
  region  = var.region
  api_key = var.mgc_api_key
}
