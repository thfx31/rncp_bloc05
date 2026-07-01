# ── Réseau privé du cluster (créé par terraform/cluster/) ─
# Récupéré par nom, pas par remote state : Vault et le cluster ont des cycles
# de vie et des états Terraform indépendants (cf. docs/poc-vs-prod.md).
data "scaleway_vpc_private_network" "cluster" {
  name = "${var.cluster_name}-private"
}

resource "scaleway_instance_ip" "vault" {
  zone = var.scw_zone
}

resource "scaleway_instance_server" "vault" {
  name  = var.vault_name
  type  = var.instance_type_vault
  image = var.image
  zone  = var.scw_zone
  ip_id = scaleway_instance_ip.vault.id

  root_volume {
    size_in_gb  = 20
    volume_type = "sbs_volume"
  }

  # Attachée au même réseau privé que le cluster : jointe pour l'auth K8s
  # (Jenkins -> Vault) sans exposer Vault publiquement au-delà de SSH/API admin.
  private_network {
    pn_id = data.scaleway_vpc_private_network.cluster.id
  }

  tags = ["project:rncp-bc05", "env:poc", "role:vault"]
}
