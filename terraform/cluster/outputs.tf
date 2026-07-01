# Outputs utilisés par ansible/inventory.py

output "control_plane_ip_public" {
  description = "IP publique du control plane RKE2"
  value       = scaleway_instance_ip.nodes["cp"].address
}

output "worker01_ip_public" {
  description = "IP publique worker-01"
  value       = scaleway_instance_ip.nodes["worker01"].address
}

output "worker02_ip_public" {
  description = "IP publique worker-02"
  value       = scaleway_instance_ip.nodes["worker02"].address
}

output "cluster_summary" {
  description = "Résumé des IPs du cluster"
  value = {
    cp       = scaleway_instance_ip.nodes["cp"].address
    worker01 = scaleway_instance_ip.nodes["worker01"].address
    worker02 = scaleway_instance_ip.nodes["worker02"].address
  }
}
