#!/bin/bash

# SRE Setup Orchestration Script
# This script orchestrates the setup process using existing scripts and README instructions
# It uses minikube.sh for cluster setup and follows README instructions for chart installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="student-api"
MONITORING_NAMESPACE="monitoring"
VAULT_NAMESPACE="vault"

echo "=========================================="
echo "SRE Implementation Setup Script"
echo "=========================================="
echo ""
echo "This script orchestrates the setup using existing infrastructure:"
echo "  - Uses minikube.sh for cluster setup"
echo "  - Follows README instructions for chart installation"
echo ""

# Check prerequisites
echo "Checking prerequisites..."
command -v minikube >/dev/null 2>&1 || { echo "✗ minikube is required but not installed. Aborting." >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "✗ kubectl is required but not installed. Aborting." >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "✗ helm is required but not installed. Aborting." >&2; exit 1; }
echo "✓ All prerequisites met"
echo ""

# Step 1: Setup Minikube cluster
echo "=========================================="
echo "Step 1: Setting up Minikube cluster"
echo "=========================================="

# Determine profile name
if [ -f "$PROJECT_ROOT/minikube.sh" ]; then
    # Extract profile name from minikube.sh
    PROFILE_NAME=$(grep -oP 'PROFILE_NAME="\K[^"]+' "$PROJECT_ROOT/minikube.sh" || echo "one2n-task")
else
    PROFILE_NAME="atlan-sre-task"
fi

# Check if cluster is already running
if minikube status -p $PROFILE_NAME &>/dev/null; then
    echo "✓ Cluster '$PROFILE_NAME' is already running"
    echo "  Current status:"
    minikube status -p $PROFILE_NAME
    echo ""
    read -p "Do you want to recreate the cluster? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Stopping existing cluster..."
        minikube stop -p $PROFILE_NAME || true
        minikube delete -p $PROFILE_NAME || true
        echo "Recreating cluster..."
    else
        echo "Using existing cluster. Verifying node labels and taints..."
        # Verify and apply labels/taints if needed
        NODES=$(kubectl get nodes -o name)
        for node in $NODES; do
            NODE_NAME=${node#node/}
            if [[ "$NODE_NAME" == *"-m02" ]]; then
                kubectl label nodes $NODE_NAME type=application --overwrite 2>/dev/null || true
                kubectl taint nodes $NODE_NAME type=application:NoSchedule --overwrite 2>/dev/null || true
            elif [[ "$NODE_NAME" == *"-m03" ]]; then
                kubectl label nodes $NODE_NAME type=database --overwrite 2>/dev/null || true
                kubectl taint nodes $NODE_NAME type=database:NoSchedule --overwrite 2>/dev/null || true
            elif [[ "$NODE_NAME" == *"-m04" ]]; then
                kubectl label nodes $NODE_NAME type=dependent_services --overwrite 2>/dev/null || true
                kubectl taint nodes $NODE_NAME type=dependent_services:NoSchedule --overwrite 2>/dev/null || true
            fi
        done
        echo "✓ Cluster is ready"
        echo ""
        # Skip to next step
        SKIP_CLUSTER_SETUP=true
    fi
fi

# Setup cluster if not skipping
if [ "${SKIP_CLUSTER_SETUP:-false}" != "true" ]; then
    echo "Setting up Minikube cluster..."
    if [ -f "$PROJECT_ROOT/minikube.sh" ]; then
        bash "$PROJECT_ROOT/minikube.sh"
    else
        echo "⚠ Warning: minikube.sh not found. Setting up cluster manually..."
        minikube start --nodes 4 -p $PROFILE_NAME --memory 2048 --cpus 4
        kubectl wait --for=condition=ready node --all --timeout=300s
        kubectl label nodes $PROFILE_NAME $PROFILE_NAME-m02 type=application --overwrite
        kubectl label nodes $PROFILE_NAME $PROFILE_NAME-m03 type=database --overwrite
        kubectl label nodes $PROFILE_NAME $PROFILE_NAME-m04 type=dependent_services --overwrite
        kubectl taint nodes $PROFILE_NAME-m02 type=application:NoSchedule --overwrite
        kubectl taint nodes $PROFILE_NAME-m03 type=database:NoSchedule --overwrite
        kubectl taint nodes $PROFILE_NAME-m04 type=dependent_services:NoSchedule --overwrite
    fi
fi
echo ""

# Step 2: Create namespaces
echo "=========================================="
echo "Step 2: Creating namespaces"
echo "=========================================="
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace $MONITORING_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace $VAULT_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Label namespaces for network policies
kubectl label namespace $MONITORING_NAMESPACE name=monitoring --overwrite || true
kubectl label namespace $VAULT_NAMESPACE name=vault --overwrite || true
echo "✓ Namespaces created"
echo ""

# Step 3: Install Monitoring Stack
echo "=========================================="
echo "Step 3: Installing Monitoring Stack"
echo "=========================================="
echo "Following instructions from charts/monitoring/README.md"
echo "Command: helm upgrade --install observability charts/monitoring -f charts/monitoring/values.yaml -n $MONITORING_NAMESPACE"
cd "$PROJECT_ROOT"
helm upgrade --install observability charts/monitoring -f charts/monitoring/values.yaml -n $MONITORING_NAMESPACE --create-namespace
echo "✓ Monitoring stack installation initiated"
echo "  Note: Wait for pods to be ready before proceeding"
echo ""

# Step 4: Install Vault (optional)
echo "=========================================="
echo "Step 4: Installing Vault (Optional)"
echo "=========================================="
read -p "Do you want to install Vault? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Following instructions from charts/vault/README.md"
    echo "Command: helm upgrade --install vault-setup charts/vault -n $VAULT_NAMESPACE"
    helm upgrade --install vault-setup charts/vault -n $VAULT_NAMESPACE --create-namespace
    echo "✓ Vault installation initiated"
    echo "  Note: Follow vault/README.md for initialization steps"
else
    echo "⏭ Skipping Vault installation"
fi
echo ""

# Step 5: Install External Secrets Operator (optional)
echo "=========================================="
echo "Step 5: Installing External Secrets Operator (Optional)"
echo "=========================================="
read -p "Do you want to install External Secrets Operator? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Following instructions from charts/external-secrets/README.md"
    echo "Command: helm upgrade --install external-secrets charts/external-secrets -n $VAULT_NAMESPACE"
    helm upgrade --install external-secrets charts/external-secrets -n $VAULT_NAMESPACE --create-namespace
    echo "✓ External Secrets Operator installation initiated"
else
    echo "⏭ Skipping External Secrets Operator installation"
fi
echo ""

# Step 6: Deploy Student API
echo "=========================================="
echo "Step 6: Deploying Student API"
echo "=========================================="
echo "Following instructions from charts/crud-api/README.md"
echo ""

# Check if Vault is installed
VAULT_INSTALLED=false
if kubectl get pods -n $VAULT_NAMESPACE -l app.kubernetes.io/name=vault 2>/dev/null | grep -q Running; then
    VAULT_INSTALLED=true
fi

if [ "$VAULT_INSTALLED" = true ]; then
    echo "✓ Vault is installed"
    echo ""
    echo "⚠ IMPORTANT: Before deploying with External Secrets, ensure:"
    echo "  1. Vault is initialized and unsealed"
    echo "  2. Vault token secret is created:"
    echo "     kubectl create secret generic vault-token-secret \\"
    echo "       --from-literal=vault-token=<your-vault-token> \\"
    echo "       -n $NAMESPACE"
    echo "  3. Secrets are stored in Vault at path: kv/postgres-secret"
    echo ""
    read -p "Deploy with External Secrets enabled? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Command: helm upgrade --install student-crud-api charts/crud-api -n $NAMESPACE --create-namespace"
        helm upgrade --install student-crud-api charts/crud-api -n $NAMESPACE --create-namespace
        echo "✓ Student API deployment initiated (with External Secrets)"
    else
        echo "Deploying without External Secrets (using Kubernetes secrets)..."
        echo "Command: helm upgrade --install student-crud-api charts/crud-api -n $NAMESPACE --create-namespace --set externalSecret.enabled=false"
        helm upgrade --install student-crud-api charts/crud-api -n $NAMESPACE --create-namespace --set externalSecret.enabled=false
        echo "✓ Student API deployment initiated (without External Secrets)"
        echo "  Note: Ensure Kubernetes secrets are created manually if needed"
    fi
else
    echo "⚠ Vault is not installed"
    echo ""
    echo "You can still deploy Student API without External Secrets:"
    echo "  - Set externalSecret.enabled=false"
    echo "  - The chart will use regular Kubernetes secrets"
    echo ""
    read -p "Deploy Student API without External Secrets? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Command: helm upgrade --install student-crud-api charts/crud-api -n $NAMESPACE --create-namespace --set externalSecret.enabled=false"
        helm upgrade --install student-crud-api charts/crud-api -n $NAMESPACE --create-namespace --set externalSecret.enabled=false
        echo "✓ Student API deployment initiated (without External Secrets)"
    else
        echo "⏭ Skipping Student API deployment"
        echo "  You can deploy later using:"
        echo "  helm upgrade --install student-crud-api charts/crud-api -n $NAMESPACE --set externalSecret.enabled=false"
    fi
fi
echo ""

# Step 7: Apply Prometheus Alerts
echo "=========================================="
echo "Step 7: Applying Prometheus Alert Rules"
echo "=========================================="
if [ -f "$SCRIPT_DIR/../prometheus-alerts/student-api-alerts.yaml" ]; then
    echo "Applying Prometheus alert rules..."
    kubectl apply -f "$SCRIPT_DIR/../prometheus-alerts/student-api-alerts.yaml" -n $MONITORING_NAMESPACE || {
        echo "⚠ Note: Alert rules may need to be applied as PrometheusRule CRD"
        echo "  Check charts/monitoring/README.md for alert configuration"
    }
    echo "✓ Alert rules applied"
else
    echo "⚠ Alert rules file not found"
fi
echo ""

# Final Status
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo "1. Wait for all pods to be ready:"
echo "   kubectl get pods -n $MONITORING_NAMESPACE"
echo "   kubectl get pods -n $NAMESPACE"
echo ""
echo "2. Import Grafana dashboard:"
echo "   - Access Grafana: kubectl port-forward svc/observability-grafana 3000:80 -n $MONITORING_NAMESPACE"
echo "   - Import: deliverables/grafana-dashboards/student-api-dashboard.json"
echo ""
echo "3. Verify deployment:"
echo "   ./deliverables/scripts/verify-deployment.sh"
echo ""
echo "4. Troubleshoot if needed:"
echo "   ./deliverables/scripts/troubleshoot.sh"
echo ""
echo "For detailed instructions, refer to:"
echo "  - charts/monitoring/README.md"
echo "  - charts/crud-api/README.md"
echo "  - charts/vault/README.md (if using Vault)"
echo ""

