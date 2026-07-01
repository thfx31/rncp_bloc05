terraform {
  backend "s3" {
    bucket = "terraform-state-rncp-bc05"
    key    = "cluster/terraform.tfstate"
    region = "fr-par"

    endpoints = {
      s3 = "https://s3.fr-par.scw.cloud"
    }

    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    use_path_style              = true

    # Credentials via variables d'environnement :
    #   TF_BACKEND_ACCESS_KEY (= AWS_ACCESS_KEY_ID)
    #   TF_BACKEND_SECRET_KEY (= AWS_SECRET_ACCESS_KEY)
  }
}
