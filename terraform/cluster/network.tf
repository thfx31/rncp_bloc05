resource "scaleway_vpc_private_network" "cluster" {
  name   = "${var.cluster_name}-private"
  region = var.scw_region

  tags = ["project:rncp-bc05", "managed-by:terraform"]
}
