locals {
  controlplane_nodes = {
    for key, node in var.nodes : key => node
    if node.role == "controlplane"
  }

  worker_nodes = {
    for key, node in var.nodes : key => node
    if node.role == "worker"
  }

  node_ips = [
    for key in sort(keys(var.nodes)) : var.nodes[key].ip
  ]

  controlplane_ips = [
    for key in sort(keys(local.controlplane_nodes)) : local.controlplane_nodes[key].ip
  ]

  bootstrap_node_ip = local.controlplane_ips[0]

  talos_common_config_patch = yamlencode({
    machine = {
      install = {
        disk  = var.install_disk
        image = data.talos_image_factory_urls.this.urls.installer
      }
    }
    cluster = {
      network = {
        cni = {
          name = "none"
        }
      }
    }
  })
}

