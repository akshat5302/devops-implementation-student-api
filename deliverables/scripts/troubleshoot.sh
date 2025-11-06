#!/bin/bash

# Troubleshooting script for Student API
# This script helps diagnose common issues in the Kubernetes deployment

set -e

NAMESPACE="${NAMESPACE:-student-api}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"

echo "=========================================="
echo "Student API Troubleshooting Script"
echo "=========================================="
echo ""

# Function to check pod status
check_pods() {
    echo "=== Pod Status ==="
    kubectl get pods -n $NAMESPACE
    echo ""
    
    echo "=== Pods with Issues ==="
    kubectl get pods -n $NAMESPACE -o json | jq -r '.items[] | select(.status.phase != "Running" or .status.containerStatuses[]?.ready == false) | "\(.metadata.name): \(.status.phase) - \(.status.containerStatuses[].state | to_entries | .[].key)"' 2>/dev/null || echo "No issues found or jq not installed"
    echo ""
}

# Function to check services
check_services() {
    echo "=== Service Status ==="
    kubectl get svc -n $NAMESPACE
    echo ""
    
    echo "=== Service Endpoints ==="
    for svc in $(kubectl get svc -n $NAMESPACE -o name); do
        echo "Endpoints for $svc:"
        kubectl get endpoints -n $NAMESPACE $(echo $svc | cut -d'/' -f2) -o wide
        echo ""
    done
}

# Function to check pod logs
check_logs() {
    echo "=== Recent Pod Logs (last 20 lines) ==="
    for pod in $(kubectl get pods -n $NAMESPACE -o name | grep -E "(api|frontend|db)"); do
        echo "--- Logs for $pod ---"
        kubectl logs -n $NAMESPACE $(echo $pod | cut -d'/' -f2) --tail=20 2>&1 || echo "Could not fetch logs"
        echo ""
    done
}

# Function to check pod events
check_events() {
    echo "=== Recent Events ==="
    kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -20
    echo ""
}

# Function to check resource usage
check_resources() {
    echo "=== Resource Usage ==="
    kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Metrics server not available"
    echo ""
    
    echo "=== Resource Requests/Limits ==="
    for pod in $(kubectl get pods -n $NAMESPACE -o name); do
        echo "Resources for $pod:"
        kubectl get pod -n $NAMESPACE $(echo $pod | cut -d'/' -f2) -o jsonpath='{.spec.containers[*].resources}' 2>/dev/null || echo "N/A"
        echo ""
    done
}

# Function to check network policies
check_network_policies() {
    echo "=== Network Policies ==="
    kubectl get networkpolicies -n $NAMESPACE 2>/dev/null || echo "No network policies found"
    echo ""
}

# Function to check HPA
check_hpa() {
    echo "=== Horizontal Pod Autoscalers ==="
    kubectl get hpa -n $NAMESPACE 2>/dev/null || echo "No HPAs found"
    echo ""
}

# Function to check ingress
check_ingress() {
    echo "=== Ingress ==="
    kubectl get ingress -n $NAMESPACE
    echo ""
}

# Function to check database connectivity
check_database() {
    echo "=== Database Connectivity Test ==="
    API_POD=$(kubectl get pods -n $NAMESPACE -l app=student-crud-api-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$API_POD" ]; then
        echo "Testing database connection from API pod: $API_POD"
        kubectl exec -n $NAMESPACE $API_POD -- pg_isready -h student-crud-api-api-db -p 5432 2>/dev/null && echo "Database is reachable" || echo "Database is NOT reachable"
    else
        echo "No API pod found"
    fi
    echo ""
}

# Function to check health endpoints
check_health() {
    echo "=== Health Endpoint Check ==="
    API_POD=$(kubectl get pods -n $NAMESPACE -l app=student-crud-api-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$API_POD" ]; then
        echo "Checking health endpoint from API pod: $API_POD"
        kubectl exec -n $NAMESPACE $API_POD -- wget -qO- http://localhost:3000/api/v1/health 2>/dev/null || echo "Health endpoint not responding"
    else
        echo "No API pod found"
    fi
    echo ""
}

# Function to check monitoring
check_monitoring() {
    echo "=== Monitoring Stack Status ==="
    kubectl get pods -n $MONITORING_NAMESPACE 2>/dev/null || echo "Monitoring namespace not found"
    echo ""
    
    echo "=== Prometheus Targets ==="
    PROM_POD=$(kubectl get pods -n $MONITORING_NAMESPACE -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$PROM_POD" ]; then
        echo "Prometheus pod: $PROM_POD"
        kubectl exec -n $MONITORING_NAMESPACE $PROM_POD -- wget -qO- http://localhost:9090/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets[] | select(.health != "up") | "\(.labels.job): \(.health) - \(.lastError)"' 2>/dev/null || echo "All targets are up or jq not installed"
    else
        echo "Prometheus pod not found"
    fi
    echo ""
}

# Main execution
check_pods
check_services
check_events
check_resources
check_network_policies
check_hpa
check_ingress
check_database
check_health
check_monitoring

echo "=========================================="
echo "Troubleshooting Complete"
echo "=========================================="
echo ""
echo "Common Issues and Solutions:"
echo "1. Pods in CrashLoopBackOff: Check logs with 'kubectl logs <pod-name> -n $NAMESPACE'"
echo "2. No endpoints for service: Check pod labels match service selector"
echo "3. Database connection issues: Verify database pod is running and network policies allow traffic"
echo "4. High memory/CPU: Check resource limits and consider scaling"
echo "5. Network policy blocking: Check network policies and namespace labels"

