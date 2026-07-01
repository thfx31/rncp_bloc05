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
  description = "Doit correspondre au cluster_name de terraform/cluster/ — sert à retrouver le réseau privé existant par nom (\"$${cluster_name}-private\")"
  type        = string
  default     = "rncp-bc05"
}

variable "vault_name" {
  description = "Nom de la VM Vault"
  type        = string
  default     = "rncp-bc05-vault"
}

variable "instance_type_vault" {
  description = "Type d'instance Scaleway pour Vault (petit gabarit, single-node raft)"
  type        = string
  default     = "DEV1-S"
}

variable "image" {
  description = "Image Scaleway — vérifier le nom exact : scw marketplace image list | grep -i alma"
  type        = string
  default     = "almalinux_9"
}
