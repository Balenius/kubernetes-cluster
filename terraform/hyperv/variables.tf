variable "hyperv_host" {
    default = "127.0.0.1"
}

variable "hyperv_user" {
    default = "hyperv"
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
    default = "5985"
}

variable "hyperv_winrm_https" {
    default = "false"
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

variable "build_dir" {
    default = "C:/HyperV/build"
}

variable "vhd_destination_path" {
    default = "E:/Hyper-V/terraform"
}

variable "ssh_authorized_key" {
    type = string
}

variable "console_password" {
  type        = string
  description = "console emergency password in case locked out by fw rule"
  sensitive   = true
}