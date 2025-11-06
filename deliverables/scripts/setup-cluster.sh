#!/bin/bash

# Setup script for Student API Kubernetes cluster
# This script sets up a multi-node Minikube cluster with proper labels and deploys the application

set -e

PROFILE_NAME="atlan-sre-task"
NAMESPACE="student-api"
MONITORING_NAMESPACE="monitoring"
VAULT_NAMESPACE="vault"

echo "=========================================="
echo "Student API Cluster Setup Script"
echo "=========================================="

# Check prerequisites
echo "Checking prerequisites..."
command -v minikube >/dev/null 2>&1 || { echo "minikube is required but not installed. Aborting." >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed. Aborting." >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "helm is required but not installed. Aborting." >&2; exit 1; }

# Start Minikube cluster
echo ""
echo "Starting Minikube cluster with 4 nodes..."
minikube start --nodes 4 -p $PROFILE_NAME --memory 2048 --cpus 4

# Wait for nodes to be ready
echo "Waiting for nodes to be ready..."
kubectl wait --for=condition=ready node --all --timeout=300s

# Label the nodes
echo ""
echo "Labeling nodes..."
kubectl label nodes $PROFILE_NAME type=control-plane --overwrite
kubectl label nodes $PROFILE_NAME-m02 type=application --overwrite
kubectl label nodes $PROFILE_NAME-m03 type=database --overwrite
kubectl label nodes $PROFILE_NAME-m04 type=dependent_services --overwrite

# Taint nodes for pod placement
echo "Tainting nodes for pod placement..."
kubectl taint nodes $PROFILE_NAME-m02 type=application:NoSchedule --overwrite
kubectl taint nodes $PROFILE_NAME-m03 type=database:NoSchedule --overwrite
kubectl taint nodes $PROFILE_NAME-m04 type=dependent_services:NoSchedule --overwrite

# Verify node labels
echo ""
echo "Verifying node labels:"
kubectl get nodes --show-labels

# Create namespaces
echo ""
echo "Creating namespaces..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace $MONITORING_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace $VAULT_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Label namespaces for network policies
echo "Labeling namespaces..."
kubectl label namespace $MONITORING_NAMESPACE name=monitoring --overwrite
kubectl label namespace $VAULT_NAMESPACE name=vault --overwrite

# Install monitoring stack
echo ""
echo "Installing monitoring stack..."
cd charts/monitoring
helm upgrade --install observability . -f values.yaml -n $MONITORING_NAMESPACE --create-namespace
cd ../..

# Wait for monitoring to be ready
echo "Waiting for monitoring stack to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus-operator -n $MONITORING_NAMESPACE --timeout=300s || true

# Install Vault (if needed)
echo ""
read -p "Do you want to install Vault? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Installing Vault..."
    cd charts/vault
    helm upgrade --install vault-setup . -n $VAULT_NAMESPACE --create-namespace
    cd ../..
    echo "Waiting for Vault to be ready..."
    sleep 30
fi

# Install External Secrets Operator (if needed)
echo ""
read -p "Do you want to install External Secrets Operator? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Installing External Secrets Operator..."
    cd charts/external-secrets
    helm upgrade --install external-secrets . -n $VAULT_NAMESPACE --create-namespace
    cd ../..
fi

# Deploy Student API
echo ""
echo "Deploying Student API..."
cd charts/crud-api
helm upgrade --install student-crud-api . -n $NAMESPACE --create-namespace
cd ../..

# Wait for pods to be ready
echo ""
echo "Waiting for application pods to be ready..."
kubectl wait --for=condition=ready pod -l app=student-crud-api-api -n $NAMESPACE --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=student-crud-api-frontend -n $NAMESPACE --timeout=300s || true

# Display status
echo ""
echo "=========================================="
echo "Cluster Setup Complete!"
echo "=========================================="
echo ""
echo "Cluster Information:"
kubectl cluster-info
echo ""
echo "Node Status:"
kubectl get nodes
echo ""
echo "Pod Status:"
kubectl get pods -n $NAMESPACE
echo ""
echo "Services:"
kubectl get svc -n $NAMESPACE
echo ""
echo "To access services:"
echo "  Grafana: kubectl port-forward svc/observability-grafana 3000:80 -n $MONITORING_NAMESPACE"
echo "  Prometheus: kubectl port-forward svc/observability-kube-prometheus-stack-prometheus 9090:9090 -n $MONITORING_NAMESPACE"
echo ""
echo "To use this cluster in future commands:"
echo "  minikube profile $PROFILE_NAME"

