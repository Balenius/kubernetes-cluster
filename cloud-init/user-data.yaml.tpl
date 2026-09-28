#cloud-config
hostname: ${node_name}
password: ${console_password}
chpasswd:
  expire: false
ssh_pwauth: false
ssh_authorized_keys:
    - ${ssh_authorized_key}
write_files:
  - path: /usr/local/bin/ufw-setup.sh
    permissions: '0755'
    content: |
      ${indent(6, ufw_setup_script)}

runcmd:
    - /usr/local/bin/ufw-setup.sh
    - "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${k3s_version} sh -"