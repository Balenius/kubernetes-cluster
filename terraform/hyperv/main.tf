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