#!/bin/bash
set -e
ufw default deny incoming
ufw default allow outgoing
ufw allow 80/tcp comment "HTTP"
ufw allow 6443/tcp comment "Kubernetes API Server"
ufw allow 22/tcp comment "SSH"
ufw allow from 10.42.0.0/16 to any comment "Kubernetes Cluster Network"
ufw allow from 10.43.0.0/16 to any comment "Kubernetes Cluster Network"
ufw --force enable