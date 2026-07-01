# ── Réseau privé inter-nodes ──────────────────────────────
# Scaleway VPC Private Network — pas de port_security, pas d'anti-spoofing
# Compatible Kubernetes/Cilium sans configuration spéciale
#
# Le nom de cette ressource est retrouvé par terraform/vault/ (data source, par nom)
# pour y attacher la VM Vault sans partager le state Terraform du cluster.
resource "scaleway_vpc_private_network" "cluster" {
  name   = "${var.cluster_name}-private"
  region = var.scw_region

  tags = ["project:rncp-bc05", "managed-by:terraform"]
}
