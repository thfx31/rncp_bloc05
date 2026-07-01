locals {
  nodes = {
    cp = {
      name = "${var.cluster_name}-cp-01"
      type = var.instance_type_cp
    }
    worker01 = {
      name = "${var.cluster_name}-worker-01"
      type = var.instance_type_worker
    }
    worker02 = {
      name = "${var.cluster_name}-worker-02"
      type = var.instance_type_worker
    }
  }
}

# ── IPs publiques flexibles ───────────────────────────────
resource "scaleway_instance_ip" "nodes" {
  for_each = local.nodes
  zone     = var.scw_zone
}

# ── Instances ─────────────────────────────────────────────
resource "scaleway_instance_server" "nodes" {
  for_each = local.nodes

  name  = each.value.name
  type  = each.value.type
  image = var.image
  zone  = var.scw_zone
  ip_id = scaleway_instance_ip.nodes[each.key].id

  root_volume {
    size_in_gb  = each.key == "cp" ? 40 : 80
    volume_type = "sbs_volume"
  }

  # Réseau privé inter-nodes (pas de port_security sur Scaleway)
  private_network {
    pn_id = scaleway_vpc_private_network.cluster.id
  }

  tags = ["project:rncp-bc05", "env:poc", "role:${each.key}"]
}
