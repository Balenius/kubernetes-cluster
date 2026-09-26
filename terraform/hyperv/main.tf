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
  filename = "${var.build_dir}/user-data"
  content  = templatefile("${path.module}/../../cloud-init/user-data.yaml.tpl", {
    node_name = var.node_name
    ssh_authorized_key = var.ssh_authorized_key
    k3s_version = var.k3s_version
    ufw_setup_script = file("${path.module}/../../cloud-init/ufw-setup.sh")
  })
}

resource "local_file" "network-config" {
  filename = "${var.build_dir}/network-config"
  content  = templatefile("${path.module}/../../cloud-init/network-config.yaml.tpl", {
    node_ip = var.node_ip
  })
}

resource "local_file" "meta-data" {
  filename = "${var.build_dir}/meta-data"
   content = <<-EOT
    instance-id: ${var.node_name}
    local-hostname: ${var.node_name}
    EOT
}

locals {
  build_dir_win = replace(var.build_dir, "/", "\\")
  boot_disk_path_win = replace("${var.vhd_destination_path}/${var.node_name}.vhdx", "/", "\\")
}

resource "null_resource" "build_seed_iso" {
  provisioner "local-exec" {
    command = "${var.iso_tool} -n -m -lcidata ${local.build_dir_win} ${local.build_dir_win}\\seed.iso"
  }
  triggers = { 
    user-data = local_file.user-data.content_md5
    network-config = local_file.network-config.content_md5
    meta-data = local_file.meta-data.content_md5
  }
}

resource "hyperv_vhd" "boot_disk" {
  path = local.boot_disk_path_win
  source = var.ubuntu_vhdx_source
  size = var.disk_size_bytes
}

resource "hyperv_machine_instance" "hyperv_node" {
  name = var.node_name
  generation = 2
  processor_count = var.cpus
  static_memory = true
  memory_startup_bytes = var.memory_bytes
  network_adaptors {
    name = "nic0"
    switch_name = hyperv_network_switch.main.name
    wait_for_ips = false
  }
  hard_disk_drives {
    controller_type = "Scsi"
    controller_number = 0
    controller_location = 0
    path = hyperv_vhd.boot_disk.path
  }
  dvd_drives {
    controller_number = 0
    controller_location = 1
    path = "${var.build_dir}/seed.iso"
  }
  vm_firmware {
    enable_secure_boot   = "On"
    secure_boot_template = "MicrosoftUEFICertificateAuthority"
    boot_order {
      boot_type           = "HardDiskDrive"
      controller_number   = 0
      controller_location = 0
    }
  }
  depends_on = [null_resource.build_seed_iso]
}