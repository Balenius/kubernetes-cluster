#!/bin/bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 80 proto tcp comment "HTTP"
ufw allow 6443 proto tcp comment "Kubernetes API Server"
ufw allow 22 proto tcp comment "SSH"
ufw enable --force