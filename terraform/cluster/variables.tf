variable "scw_region" {
  description = "Région Scaleway (ex: fr-par, nl-ams, pl-waw)"
  type        = string
  default     = "fr-par"
}

variable "scw_zone" {
  description = "Zone Scaleway (ex: fr-par-1, fr-par-2, nl-ams-1)"
  type        = string
  default     = "fr-par-2"
}

variable "cluster_name" {
  description = "Préfixe des noms de ressources — aussi utilisé par terraform/vault/ pour retrouver le réseau privé du cluster"
  type        = string
  default     = "rncp-bc05"
}

variable "instance_type_cp" {
  description = "Type d'instance Scaleway pour le control plane RKE2 (4 vCPU / 8 GB)"
  type        = string
  default     = "DEV1-L"
}

variable "instance_type_worker" {
  description = "Type d'instance Scaleway pour les workers RKE2 (4 vCPU / 12 GB)"
  type        = string
  default     = "DEV1-XL"
}

variable "image" {
  description = "Image Scaleway — vérifier le nom exact : scw marketplace image list | grep -i alma"
  type        = string
  default     = "almalinux_9"
}

variable "private_subnet" {
  description = "CIDR du réseau privé inter-nodes"
  type        = string
  default     = "10.0.0.0/24"
}

variable "domain" {
  description = "Domaine principal des services exposés"
  type        = string
  default     = "k8s.yplank.fr"
}
