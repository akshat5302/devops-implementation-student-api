#!/bin/bash

# Script to check if logs from student-api namespace are in Loki

NAMESPACE="${NAMESPACE:-student-api}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"

echo "=========================================="
echo "Checking Loki Logs from $NAMESPACE namespace"
echo "=========================================="
echo ""

# Check if Loki is accessible
echo "1. Checking Loki service..."
if kubectl get svc -n $MONITORING_NAMESPACE | grep -q loki; then
    echo "✓ Loki service found"
    LOKI_SVC=$(kubectl get svc -n $MONITORING_NAMESPACE -o name | grep loki | head -1)
    echo "  Service: $LOKI_SVC"
else
    echo "✗ Loki service not found"
    exit 1
fi
echo ""

# Check Promtail pods
echo "2. Checking Promtail pods..."
PROMTAIL_PODS=$(kubectl get pods -n $MONITORING_NAMESPACE -l app.kubernetes.io/name=promtail -o name 2>/dev/null | wc -l)
if [ "$PROMTAIL_PODS" -gt 0 ]; then
    echo "✓ Found $PROMTAIL_PODS Promtail pod(s)"
    for pod in $(kubectl get pods -n $MONITORING_NAMESPACE -l app.kubernetes.io/name=promtail -o name); do
        POD_NAME=$(echo $pod | cut -d'/' -f2)
        STATUS=$(kubectl get pod $POD_NAME -n $MONITORING_NAMESPACE -o jsonpath='{.status.phase}')
        echo "  - $POD_NAME: $STATUS"
    done
else
    echo "✗ No Promtail pods found"
    exit 1
fi
echo ""

# Check if Promtail is watching student-api namespace
echo "3. Checking if Promtail is collecting logs from $NAMESPACE namespace..."
PROMTAIL_POD=$(kubectl get pods -n $MONITORING_NAMESPACE -l app.kubernetes.io/name=promtail -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$PROMTAIL_POD" ]; then
    LOGS=$(kubectl logs $PROMTAIL_POD -n $MONITORING_NAMESPACE --tail=50 2>&1 | grep -i "$NAMESPACE" | head -5)
    if [ -n "$LOGS" ]; then
        echo "✓ Promtail is watching $NAMESPACE namespace:"
        echo "$LOGS" | sed 's/^/  /'
    else
        echo "⚠ No logs found mentioning $NAMESPACE namespace in Promtail logs"
    fi
else
    echo "✗ Could not find Promtail pod"
fi
echo ""

# Check application pods in student-api namespace
echo "4. Checking application pods in $NAMESPACE namespace..."
APP_PODS=$(kubectl get pods -n $NAMESPACE -o name 2>/dev/null | wc -l)
if [ "$APP_PODS" -gt 0 ]; then
    echo "✓ Found $APP_PODS pod(s) in $NAMESPACE namespace:"
    kubectl get pods -n $NAMESPACE -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName 2>/dev/null | tail -n +2
else
    echo "✗ No pods found in $NAMESPACE namespace"
fi
echo ""

# Try to query Loki for logs
echo "5. Querying Loki for logs from $NAMESPACE namespace..."
LOKI_POD=$(kubectl get pods -n $MONITORING_NAMESPACE -l app.kubernetes.io/name=loki -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$LOKI_POD" ]; then
    # Query for namespace label
    NAMESPACES=$(kubectl exec $LOKI_POD -n $MONITORING_NAMESPACE -- wget -qO- "http://localhost:3100/loki/api/v1/label/namespace/values" 2>/dev/null | grep -o "\"$NAMESPACE\"" | head -1)
    if [ -n "$NAMESPACES" ]; then
        echo "✓ Found $NAMESPACE namespace in Loki labels"
        
        # Try to get recent logs
        echo "  Attempting to query recent logs..."
        RECENT_LOGS=$(kubectl exec $LOKI_POD -n $MONITORING_NAMESPACE -- wget -qO- "http://localhost:3100/loki/api/v1/query_range?query={namespace=\"$NAMESPACE\"}&limit=5" 2>/dev/null | head -20)
        if echo "$RECENT_LOGS" | grep -q "values\|streams"; then
            echo "✓ Logs found in Loki!"
            echo "  Sample query result (first 5 lines):"
            echo "$RECENT_LOGS" | head -10 | sed 's/^/  /'
        else
            echo "⚠ No logs found in Loki for $NAMESPACE namespace"
            echo "  This might mean:"
            echo "    - Logs haven't been ingested yet (wait a few minutes)"
            echo "    - Promtail configuration needs to be updated"
            echo "    - Check Promtail logs for errors"
        fi
    else
        echo "⚠ $NAMESPACE namespace not found in Loki labels"
        echo "  This means no logs from this namespace have been ingested yet"
    fi
else
    echo "✗ Could not find Loki pod"
fi
echo ""

# Check Promtail configuration
echo "6. Checking Promtail configuration..."
if [ -n "$PROMTAIL_POD" ]; then
    CONFIG=$(kubectl exec $PROMTAIL_POD -n $MONITORING_NAMESPACE -- cat /etc/promtail/promtail.yaml 2>/dev/null | grep -A 5 "scrape_configs" | head -10)
    if echo "$CONFIG" | grep -q "kubernetes_sd_configs\|scrape_configs"; then
        echo "✓ Promtail has Kubernetes scraping configured"
    else
        echo "⚠ Promtail Kubernetes scraping might not be configured"
        echo "  Configuration snippet:"
        echo "$CONFIG" | sed 's/^/  /'
    fi
fi
echo ""

echo "=========================================="
echo "Troubleshooting Tips:"
echo "=========================================="
echo ""
echo "If logs are not appearing in Loki:"
echo "1. Wait a few minutes for logs to be ingested"
echo "2. Check Promtail logs: kubectl logs -n $MONITORING_NAMESPACE -l app.kubernetes.io/name=promtail"
echo "3. Verify Promtail is running on the same node as your application pods"
echo "4. Check Loki logs: kubectl logs -n $MONITORING_NAMESPACE -l app.kubernetes.io/name=loki"
echo "5. Query Loki directly: kubectl port-forward -n $MONITORING_NAMESPACE svc/observability-loki 3100:3100"
echo "   Then visit: http://localhost:3100/ready"
echo ""
echo "To query logs in Grafana:"
echo "1. Access Grafana: kubectl port-forward -n $MONITORING_NAMESPACE svc/observability-grafana 3000:80"
echo "2. Go to Explore → Select Loki datasource"
echo "3. Query: {namespace=\"$NAMESPACE\"}"
echo ""

