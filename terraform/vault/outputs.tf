output "vault_ip_public" {
  description = "IP publique de la VM Vault"
  value       = scaleway_instance_ip.vault.address
}
