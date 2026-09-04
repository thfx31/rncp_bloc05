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

  private_network {
    pn_id = data.scaleway_vpc_private_network.cluster.id
  }

  tags = ["project:rncp-bc05", "env:poc", "role:vault"]
}
