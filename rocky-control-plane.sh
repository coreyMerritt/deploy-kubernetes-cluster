#!/usr/bin/env bash

set -euo pipefail

KUBERNETES_CONTROL_PLANE_DNS_NAME="kubernetes-control-plane-1.lan"
KUBERNETES_CONTROL_PLANE_HOSTNAME="kubernetes-control-plane-1"
KUBERNETES_CONTROL_PLANE_IP_ADDRESS="10.0.5.99"
KUBEADM_MARKER="/etc/kubernetes/admin.conf"
POD_CIDR="10.244.0.0/16"

# Set hostname
hostnamectl set-hostname "$KUBERNETES_CONTROL_PLANE_HOSTNAME"

# Install packages
dnf update -y
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf install -y \
  tar \
  dnf-plugins-core \
  containerd.io \
  conntrack-tools \
  openssl \
  curl \
  iscsi-initiator-utils
systemctl enable --now iscsid

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

# Initialize the control plane
if [ -f "$KUBEADM_MARKER" ]; then
  echo "[INFO] Kubernetes control plane already initialized (found $KUBEADM_MARKER). Skipping kubeadm init."
else
  echo "[INFO] No existing control plane found. Running kubeadm init..."
  kubeadm init \
    --pod-network-cidr "$POD_CIDR" \
    --upload-certs \
    --apiserver-cert-extra-sans "${KUBERNETES_CONTROL_PLANE_DNS_NAME},${KUBERNETES_CONTROL_PLANE_HOSTNAME},${KUBERNETES_CONTROL_PLANE_IP_ADDRESS}"
  read -p "Take note of the output of this command to assign worker vars"
fi

# Set up kubectl access for the invoking (non-root) user
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
mkdir -p "$TARGET_HOME/.kube"
cp /etc/kubernetes/admin.conf "$TARGET_HOME/.kube/config"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.kube/config"
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config

# Deploy flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Verify 
echo "[INFO] Waiting 30s before checking pod status..."
sleep 30
kubectl get pods -n kube-system | grep cilium
kubectl get nodes
