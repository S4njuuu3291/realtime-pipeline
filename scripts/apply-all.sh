#!/bin/bash
set -euo pipefail

# alias kubectl = "minicube kubectl --"

kubectl() {
    minikube kubectl -- "$@"
}

NAMESPACE="cdc-pipeline"
K8S_DIR="k8s"


echo "📁 [1/5] Creating namespace..."
kubectl apply -f "$K8S_DIR/namespace.yaml"

echo "🔐 [2/5] Applying configmap..."
kubectl apply -f "$K8S_DIR/base/configmaps.yaml" -n "$NAMESPACE"

echo "🔐 [3/5] Applying secrets..."
kubectl apply -f "$K8S_DIR/base/secrets.yaml" -n "$NAMESPACE"

echo "🔗 [4/5] Applying postgres service..."
kubectl apply -f "$K8S_DIR/postgres/service.yaml" -n "$NAMESPACE"

echo "📦 [5/5] Applying postgres statefulset..."
kubectl apply -f "$K8S_DIR/postgres/statefulset.yaml" -n "$NAMESPACE"

echo ""
echo "⏳ Waiting for postgres pod to be ready..."
kubectl wait --for=condition=ready pod
    -l app=postgres-source \
    -n "$NAMESPACE" \
    --timeout=120s 2>/dev/null || echo "  ⚠️  Timeout. Cek: kubectl get pods -n $NAMESPACE"

echo ""
echo "✅ Done!"
kubectl get pods -n "$NAMESPACE" -l app=postgres-source
