network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - ${node_ip}/24
      routes:
        - to: default
          via: 192.168.50.1
      nameservers:
        addresses:
          - 192.168.50.1 
          - 8.8.8.8
