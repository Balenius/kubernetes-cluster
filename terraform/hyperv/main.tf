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

resource "local_file" "user_data" {
  filename = "${path.module}/build/user-data"
  content  = templatefile("${path.module}/../../cloud-init/user-data.yaml.tpl", {
    node_name = var.node_name
    ssh_authorized_key = var.ssh_authorized_key
    k3s_version = var.k3s_version
    ufw_setup_script = file("${path.module}/../../cloud-init/ufw-setup.sh")
  })
}