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
# Helm chart index fetch can flake on UDP DNS / GitHub pages; retry.
for attempt in 1 2 3 4 5; do
  if helm repo add cilium https://helm.cilium.io/ --force-update >/dev/null 2>&1 \
    && helm repo update cilium >/dev/null 2>&1; then
    break
  fi
  echo "    helm repo update failed (attempt ${attempt}/5); retrying…"
  sleep $((attempt * 3))
  if [[ $attempt -eq 5 ]]; then
    echo "ERROR: cannot update helm.cilium.io — check DNS (AdGuard .14) and HTTPS egress" >&2
    exit 1
  fi
done

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
  --set k8sServiceHost="${K8S_API_HOST:-192.168.68.17}" \
  --set k8sServicePort=6443

echo "==> Applying CiliumLoadBalancerIPPool + L2AnnouncementPolicy"
kubectl apply -f "${ROOT}/config/cilium/lb-ipam-pool.yaml"
kubectl apply -f "${ROOT}/config/cilium/l2-policy.yaml"

echo "==> Cilium install complete"
kubectl -n kube-system get pods -l app.kubernetes.io/part-of=cilium ||
  kubectl -n kube-system get pods -l k8s-app=cilium
