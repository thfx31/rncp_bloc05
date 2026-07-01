terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
  }
  required_version = ">= 1.5.0"
}

# Provider Scaleway — credentials via variables d'environnement :
#   SCW_ACCESS_KEY
#   SCW_SECRET_KEY
#   SCW_DEFAULT_PROJECT_ID
#   SCW_DEFAULT_REGION
#   SCW_DEFAULT_ZONE
provider "scaleway" {}
