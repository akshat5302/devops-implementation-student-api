#!/bin/bash

# Script to test all Prometheus alerts for the Student API
# This script triggers various alert conditions to verify alerting is working

set -e

API_URL="${API_URL:-http://student-api.atlan.com}"
NAMESPACE="${NAMESPACE:-student-api}"
SERVICE_NAME="${SERVICE_NAME:-student-crud-api-api}"

echo "=========================================="
echo "Student API Alert Testing Script"
echo "=========================================="
echo "API URL: $API_URL"
echo "Namespace: $NAMESPACE"
echo ""

# Function to make API calls
call_api() {
    local endpoint=$1
    local method=${2:-GET}
    local data=${3:-""}
    
    if [ "$method" = "GET" ]; then
        curl -s -w "\nHTTP Status: %{http_code}\n" "$API_URL$endpoint" || true
    else
        curl -s -X "$method" -H "Content-Type: application/json" \
            -d "$data" -w "\nHTTP Status: %{http_code}\n" "$API_URL$endpoint" || true
    fi
    echo ""
}

# Function to trigger multiple requests
trigger_multiple() {
    local endpoint=$1
    local count=${2:-10}
    local delay=${3:-0.1}
    
    echo "Triggering $count requests to $endpoint..."
    for i in $(seq 1 $count); do
        call_api "$endpoint" > /dev/null 2>&1 &
        sleep $delay
    done
    wait
    echo "Completed $count requests"
    echo ""
}

echo "1. Testing High HTTP Error Rate Alert"
echo "   Triggering multiple 500 errors..."
trigger_multiple "/api/v1/test/trigger-errors?count=1&status=500" 50 0.2
echo "   Wait 5 minutes for alert to fire (rate > 0.1 errors/sec)"
echo ""

echo "2. Testing High Latency Alerts (P90, P95, P99)"
echo "   Triggering slow requests..."
echo "   - P90 threshold: > 1s"
call_api "/api/v1/test/trigger-alerts?alertType=high-latency&delay=1500" &
echo "   - P95 threshold: > 2s"
call_api "/api/v1/test/trigger-alerts?alertType=high-latency&delay=2500" &
echo "   - P99 threshold: > 5s"
call_api "/api/v1/test/trigger-alerts?alertType=high-latency&delay=6000" &
wait
echo "   Wait 5 minutes for latency alerts to fire"
echo ""

echo "3. Testing Database Error Alert"
echo "   Triggering database errors..."
trigger_multiple "/api/v1/test/trigger-alerts?alertType=database-error" 20 0.3
echo "   Wait 5 minutes for alert to fire (rate > 0.05 errors/sec)"
echo ""

echo "4. Testing High Database Connections Alert"
echo "   Triggering high connection count..."
call_api "/api/v1/test/trigger-alerts?alertType=high-db-connections"
echo "   Wait 5 minutes for alert to fire (connections > 50)"
echo ""

echo "5. Testing Slow Database Queries Alert"
echo "   Triggering slow queries..."
trigger_multiple "/api/v1/test/trigger-alerts?alertType=slow-db-query&delay=2000" 10 0.5
echo "   Wait 10 minutes for alert to fire (p95 > 1s)"
echo ""

echo "6. Testing High CPU Usage Alert"
echo "   Triggering CPU-intensive operations..."
call_api "/api/v1/test/trigger-alerts?alertType=cpu-intensive&iterations=100000000" &
call_api "/api/v1/test/trigger-alerts?alertType=cpu-intensive&iterations=100000000" &
call_api "/api/v1/test/trigger-alerts?alertType=cpu-intensive&iterations=100000000" &
wait
echo "   Wait 10 minutes for alert to fire (CPU > 80%)"
echo ""

echo "7. Testing High Memory Usage Alert"
echo "   Triggering memory-intensive operations..."
call_api "/api/v1/test/trigger-alerts?alertType=memory-intensive&size=10000000"
echo "   Wait 10 minutes for alert to fire (Memory > 85%)"
echo ""

echo "8. Testing Pod CrashLoopBackOff Alert"
echo "   WARNING: This will crash the pod!"
read -p "   Do you want to trigger a pod crash? (yes/no): " confirm
if [ "$confirm" = "yes" ]; then
    call_api "/api/v1/test/trigger-alerts?alertType=crash"
    echo "   Pod will crash and restart. Wait 5 minutes for alert to fire"
else
    echo "   Skipped pod crash test"
fi
echo ""

echo "9. Testing Pod Restart Count Alert"
echo "   To test this, manually restart the pod multiple times:"
echo "   kubectl delete pod -n $NAMESPACE -l app=$SERVICE_NAME"
echo "   Repeat 6+ times within an hour"
echo ""

echo "10. Testing Service Endpoints Down Alert"
echo "    To test this, scale down the deployment:"
echo "    kubectl scale deployment $SERVICE_NAME -n $NAMESPACE --replicas=0"
echo "    Wait 5 minutes for alert to fire"
echo "    Then scale back up:"
echo "    kubectl scale deployment $SERVICE_NAME -n $NAMESPACE --replicas=1"
echo ""

echo "=========================================="
echo "Alert Testing Complete!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo "1. Check Prometheus alerts: kubectl get prometheusrules -n monitoring"
echo "2. View alerts in Grafana: http://localhost:3000 (or port-forward Grafana)"
echo "3. Check AlertManager: kubectl port-forward -n monitoring svc/observability-kube-prometh-alertmanager 9093:9093"
echo "4. View metrics: curl $API_URL/metrics | grep -E '(http_errors_total|http_request_duration_seconds|db_error_total|db_connection_count)'"
echo ""

