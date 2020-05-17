#!/bin/bash
set -exuo pipefail
hostnamectl set-hostname $(curl http://169.254.169.254/latest/meta-data/hostname)
#cat <<EOT > /etc/systemd/system/kubelet.service.d/20-aws.conf
#[Service]
#Environment="KUBELET_EXTRA_ARGS=--cloud-provider=aws --node-ip=$(curl http://169.254.169.254/latest/meta-data/local-ipv4) --node-labels=node-role.kubernetes.io/node"
#EOT
systemctl daemon-reload
systemctl restart kubelet
kubeadm join 10.0.0.10:6443 --token hi56rz.95jbaj3x820lyrrz \
    --discovery-token-ca-cert-hash sha256:20ddd0cc5fe3e0e228af4082c140e07ce0af295b9a95e80cb7e27142adecf27d 

