#!/bin/bash

# Verification script for Student API deployment
# This script verifies that the deployment is healthy and functioning correctly

set -e

NAMESPACE="${NAMESPACE:-student-api}"
TIMEOUT=300

echo "=========================================="
echo "Student API Deployment Verification"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

# Check if namespace exists
echo "1. Checking namespace..."
if kubectl get namespace $NAMESPACE &>/dev/null; then
    print_status 0 "Namespace $NAMESPACE exists"
else
    print_status 1 "Namespace $NAMESPACE does not exist"
    exit 1
fi

# Check if pods are running
echo ""
echo "2. Checking pod status..."
ALL_PODS_READY=true
for pod in $(kubectl get pods -n $NAMESPACE -o name); do
    POD_NAME=$(echo $pod | cut -d'/' -f2)
    STATUS=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.phase}')
    READY=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].ready}')
    
    if [ "$STATUS" == "Running" ] && [ "$READY" == "true" ]; then
        print_status 0 "Pod $POD_NAME is Running and Ready"
    else
        print_status 1 "Pod $POD_NAME is $STATUS (Ready: $READY)"
        ALL_PODS_READY=false
    fi
done

if [ "$ALL_PODS_READY" = false ]; then
    echo -e "${YELLOW}Warning: Not all pods are ready. Waiting up to ${TIMEOUT}s...${NC}"
    kubectl wait --for=condition=ready pod -l app=student-crud-api-api -n $NAMESPACE --timeout=${TIMEOUT}s || true
    kubectl wait --for=condition=ready pod -l app=student-crud-api-frontend -n $NAMESPACE --timeout=${TIMEOUT}s || true
fi

# Check services
echo ""
echo "3. Checking services..."
for svc in api frontend api-db; do
    if kubectl get svc student-crud-api-$svc -n $NAMESPACE &>/dev/null; then
        ENDPOINTS=$(kubectl get endpoints student-crud-api-$svc -n $NAMESPACE -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
        if [ "$ENDPOINTS" -gt 0 ]; then
            print_status 0 "Service student-crud-api-$svc has $ENDPOINTS endpoint(s)"
        else
            print_status 1 "Service student-crud-api-$svc has no endpoints"
        fi
    else
        print_status 1 "Service student-crud-api-$svc does not exist"
    fi
done

# Check health endpoint
echo ""
echo "4. Checking API health endpoint..."
API_POD=$(kubectl get pods -n $NAMESPACE -l app=student-crud-api-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$API_POD" ]; then
    HEALTH_RESPONSE=$(kubectl exec -n $NAMESPACE $API_POD -- wget -qO- http://localhost:3000/api/v1/health 2>/dev/null || echo "ERROR")
    if [[ "$HEALTH_RESPONSE" == *"healthy"* ]] || [[ "$HEALTH_RESPONSE" == *"ok"* ]]; then
        print_status 0 "API health endpoint is responding"
    else
        print_status 1 "API health endpoint is not responding correctly: $HEALTH_RESPONSE"
    fi
else
    print_status 1 "No API pod found"
fi

# Check database connectivity
echo ""
echo "5. Checking database connectivity..."
if [ -n "$API_POD" ]; then
    DB_CHECK=$(kubectl exec -n $NAMESPACE $API_POD -- pg_isready -h student-crud-api-api-db -p 5432 2>&1)
    if echo "$DB_CHECK" | grep -q "accepting connections"; then
        print_status 0 "Database is reachable from API pod"
    else
        print_status 1 "Database is not reachable: $DB_CHECK"
    fi
fi

# Test API endpoints
echo ""
echo "6. Testing API endpoints..."
if [ -n "$API_POD" ]; then
    # Test GET /api/v1/students
    STUDENTS_RESPONSE=$(kubectl exec -n $NAMESPACE $API_POD -- wget -qO- http://localhost:3000/api/v1/students 2>/dev/null || echo "ERROR")
    if echo "$STUDENTS_RESPONSE" | grep -qE "(students|\[\])"; then
        print_status 0 "GET /api/v1/students endpoint is working"
    else
        print_status 1 "GET /api/v1/students endpoint returned: $STUDENTS_RESPONSE"
    fi
    
    # Test POST /api/v1/students
    TEST_STUDENT='{"name":"Test Student","email":"test@example.com","age":20}'
    POST_RESPONSE=$(kubectl exec -n $NAMESPACE $API_POD -- sh -c "echo '$TEST_STUDENT' | wget --post-data='$TEST_STUDENT' --header='Content-Type: application/json' -qO- http://localhost:3000/api/v1/students 2>/dev/null" || echo "ERROR")
    if echo "$POST_RESPONSE" | grep -qE "(id|name)"; then
        print_status 0 "POST /api/v1/students endpoint is working"
    else
        print_status 1 "POST /api/v1/students endpoint returned: $POST_RESPONSE"
    fi
fi

# Check metrics endpoint
echo ""
echo "7. Checking metrics endpoint..."
if [ -n "$API_POD" ]; then
    METRICS_RESPONSE=$(kubectl exec -n $NAMESPACE $API_POD -- wget -qO- http://localhost:3000/metrics 2>/dev/null | head -5)
    if echo "$METRICS_RESPONSE" | grep -qE "(http_requests_total|# HELP)"; then
        print_status 0 "Metrics endpoint is working"
    else
        print_status 1 "Metrics endpoint is not responding correctly"
    fi
fi

# Check HPA
echo ""
echo "8. Checking Horizontal Pod Autoscalers..."
if kubectl get hpa -n $NAMESPACE &>/dev/null; then
    for hpa in $(kubectl get hpa -n $NAMESPACE -o name); do
        HPA_NAME=$(echo $hpa | cut -d'/' -f2)
        print_status 0 "HPA $HPA_NAME exists"
    done
else
    print_status 1 "No HPAs found"
fi

# Check ingress
echo ""
echo "9. Checking ingress..."
if kubectl get ingress -n $NAMESPACE &>/dev/null; then
    INGRESS_COUNT=$(kubectl get ingress -n $NAMESPACE --no-headers | wc -l)
    print_status 0 "$INGRESS_COUNT ingress resource(s) found"
else
    print_status 1 "No ingress found"
fi

# Check resource limits
echo ""
echo "10. Checking resource limits..."
for pod in $(kubectl get pods -n $NAMESPACE -o name); do
    POD_NAME=$(echo $pod | cut -d'/' -f2)
    HAS_LIMITS=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.containers[*].resources.limits}' 2>/dev/null | grep -v "^$" || echo "")
    if [ -n "$HAS_LIMITS" ]; then
        print_status 0 "Pod $POD_NAME has resource limits"
    else
        print_status 1 "Pod $POD_NAME does not have resource limits"
    fi
done

# Check health probes
echo ""
echo "11. Checking health probes..."
for pod in $(kubectl get pods -n $NAMESPACE -o name); do
    POD_NAME=$(echo $pod | cut -d'/' -f2)
    HAS_PROBES=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.containers[*].livenessProbe}' 2>/dev/null | grep -v "^$" || echo "")
    if [ -n "$HAS_PROBES" ]; then
        print_status 0 "Pod $POD_NAME has health probes configured"
    else
        print_status 1 "Pod $POD_NAME does not have health probes"
    fi
done

# Final summary
echo ""
echo "=========================================="
echo "Verification Complete"
echo "=========================================="
echo ""
echo "To view detailed pod status:"
echo "  kubectl get pods -n $NAMESPACE"
echo ""
echo "To view pod logs:"
echo "  kubectl logs <pod-name> -n $NAMESPACE"
echo ""
echo "To test API from outside cluster:"
echo "  kubectl port-forward svc/student-crud-api-api 3000:3000 -n $NAMESPACE"
echo "  curl http://localhost:3000/api/v1/health"

