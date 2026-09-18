#cloud-config
hostname: ${node_name}
ssh_authorized_keys:
    - ${ssh_authorized_key}
runcmd:
    - "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${k3s_version} sh -"
