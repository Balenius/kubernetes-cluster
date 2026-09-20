provider "hyperv" {
  user     = var.hyperv_user
  password = var.hyperv_password
  host     = var.hyperv_host
  port     = var.hyperv_winrm_port
  https    = var.hyperv_winrm_https
  insecure = true
  use_ntlm = true
}
resource "hyperv_network_switch" "main" {
  name = var.switch_name
  switch_type = "External"
  net_adapter_names = [ var.host_net_adapter_name ]
}

resource "local_file" "user-data" {
  filename = "${path.module}/build/user-data"
  content  = templatefile("${path.module}/../../cloud-init/user-data.yaml.tpl", {
    node_name = var.node_name
    ssh_authorized_key = var.ssh_authorized_key
    k3s_version = var.k3s_version
    ufw_setup_script = file("${path.module}/../../cloud-init/ufw-setup.sh")
  })
}

resource "local_file" "network-config" {
  filename = "${path.module}/build/network-config"
  content  = templatefile("${path.module}/../../cloud-init/network-config.yaml.tpl", {
    node_ip = var.node_ip
  })
}

resource "local_file" "meta-data" {
  filename = "${path.module}/build/meta-data"
   content = <<-EOT
    instance-id: ${var.node_name}
    local-hostname: ${var.node_name}
    EOT
}

resource "null_resource" "build_seed_iso" {
  provisioner "local-exec" {
    command = " ${var.iso_tool} -n -m -lcidata \"${path.module}/build\" \"${path.module}/build/seed.iso\""
  }
  triggers = { 
    user-data = local_file.user-data.content_md5
    network-config = local_file.network-config.content_md5
    meta-data = local_file.meta-data.content_md5
  }
}