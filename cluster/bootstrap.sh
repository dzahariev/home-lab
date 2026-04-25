#!/bin/bash
# Bootstrap ArgoCD into the cluster
# Run this once to install ArgoCD, then it manages everything else

set -euo pipefail

ARGOCD_VERSION="v3.3.6"
ARGOCD_NAMESPACE="argocd"
CERT_MANAGER_VERSION="v1.20.1"

echo "Installing cert-manager ${CERT_MANAGER_VERSION}..."
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

echo "Waiting for cert-manager to be ready..."
kubectl -n cert-manager rollout status deployment cert-manager --timeout=300s
kubectl -n cert-manager rollout status deployment cert-manager-webhook --timeout=300s

echo "Creating ArgoCD namespace..."
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Installing ArgoCD ${ARGOCD_VERSION}..."
kubectl apply -n "$ARGOCD_NAMESPACE" -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "Waiting for ArgoCD to be ready..."
kubectl -n "$ARGOCD_NAMESPACE" rollout status deployment argocd-server --timeout=300s

echo "Applying root ApplicationSet..."
kubectl apply -f "$(dirname "$0")/argocd/applicationset.yaml"

echo ""
echo "ArgoCD installed successfully!"
echo ""
echo "Get the initial admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "Port-forward to access the UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8443:443"
echo ""
echo "Then open: https://localhost:8443"
