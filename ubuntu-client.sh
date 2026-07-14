#!/usr/bin/env bash

set -euo pipefail

# Vars 
CONTROL_PLANE_USER="root"
CONTROL_PLANE_HOST="kubernetes-control-plane-1.lan"
CONTROL_PLANE_IP="10.0.5.0"
KUBECTL_VERSION="v1.31.14"
KUBE_DIR="${HOME}/.kube"
KUBE_CONFIG="${KUBE_DIR}/config"

# Install kubectl 
if ! command -v kubectl >/dev/null 2>&1; then
  echo "[INFO] kubectl not found, installing ${KUBECTL_VERSION}..."
  curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/kubectl
else
  echo "[INFO] kubectl already installed, skipping."
fi

# Ensure control plane hostname resolves (fallback to /etc/hosts if not) 
if ! getent hosts "${CONTROL_PLANE_HOST}" >/dev/null 2>&1; then
  echo "[INFO] ${CONTROL_PLANE_HOST} not resolvable, adding to /etc/hosts..."
  echo "${CONTROL_PLANE_IP}   ${CONTROL_PLANE_HOST}" | sudo tee -a /etc/hosts >/dev/null
fi

# Pull admin kubeconfig from control plane 
mkdir -p "${KUBE_DIR}"
scp "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOST}:/etc/kubernetes/admin.conf" "${KUBE_CONFIG}"
chmod 600 "${KUBE_CONFIG}"

# Verify access 
echo "[INFO] Verifying cluster access..."
kubectl get nodes
