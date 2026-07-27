#!/usr/bin/env bash
# Install Cilium CNI with LoadBalancer IPAM, L2 Announcements, and Gateway API.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

require_cluster
need_cmd helm

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Ensuring Gateway API CRDs (standard channel)"
if ! kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
fi

echo "==> Adding Cilium Helm repo"
helm repo add cilium https://helm.cilium.io/ >/dev/null
helm repo update cilium >/dev/null

echo "==> Installing / upgrading Cilium"
helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --wait \
  --set kubeProxyReplacement=true \
  --set gatewayAPI.enabled=true \
  --set l2announcements.enabled=true \
  --set externalIPs.enabled=true \
  --set bpf.masquerade=true \
  --set ipam.mode=cluster-pool \
  --set 'ipam.operator.clusterPoolIPv4PodCIDRList={10.244.0.0/16}' \
  --set k8sServiceHost="${K8S_API_HOST:-kube-api.lab.nasraldin.com}" \
  --set k8sServicePort=6443

echo "==> Applying CiliumLoadBalancerIPPool + L2AnnouncementPolicy"
kubectl apply -f "${ROOT}/config/cilium/lb-ipam-pool.yaml"
kubectl apply -f "${ROOT}/config/cilium/l2-policy.yaml"

echo "==> Cilium install complete"
kubectl -n kube-system get pods -l app.kubernetes.io/part-of=cilium || \
  kubectl -n kube-system get pods -l k8s-app=cilium
