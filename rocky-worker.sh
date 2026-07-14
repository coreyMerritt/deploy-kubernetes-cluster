#!/usr/bin/env bash

set -euo pipefail

[[ "$KUBERNETES_TOKEN" ]]
[[ "$KUBERNETES_CERT_HASH" ]]

# Install packages
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf install -y \
  tar \
  dnf-plugins-core \
  containerd.io \
  conntrack-tools

# Disable swap (Kubernetes requires this)
swapoff -a
sed -i '/swap/d' /etc/fstab

# Load required kernel modules
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Set required sysctl params
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# Disable firewalld
systemctl disable --now firewalld

# Install containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

# Add Kubernetes repo and install kubeadm/kubelet/kubectl
cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

# Join the worker to the control plane
kubeadm join kubernetes-control-plane-1.lan:6443 \
  --token "$KUBERNETES_TOKEN" \
  --discovery-token-ca-cert-hash "sha256:${KUBERNETES_CERT_HASH}"
