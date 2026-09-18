variable "hyperv_host" {
    default = "localhost"
}

variable "hyperv_user" {
    default = "balen"
}

variable "hyperv_password" {
  type        = string
  description = "The administrator password for the Hyper-V host or virtual machine."
  sensitive   = true
}

variable "switch_name" {
    type = string
}

variable "host_net_adapter_name" {
    default = "Ethernet 2"
}

variable "hyperv_winrm_port" {
    default = "5986"
}

variable "hyperv_winrm_https" {
    default = "true"
}

variable "node_ip" {
    default = "192.168.50.178"
}

variable "node_name" {
    type = string
}

variable "cpus" {
    default = "2"
}

variable "memory_bytes" {
    default = 4 * 1024 * 1024 * 1024
}

variable "disk_size_bytes" {
    default = 20 * 1024 * 1024 * 1024
}

variable "iso_tool" {
    default = "oscdimg"
}

variable "k3s_version" {
    default = "v1.31.5+k3s1"
}

variable "ubuntu_vhdx_source" {
    default = "C:/HyperV/images/ubuntu-24.04.vhdx"
}

variable "vhd_destination_path" {
    default = "E:/Hyper-V/terraform/"
}

variable "ssh_authorized_key" {
    type = string
}
