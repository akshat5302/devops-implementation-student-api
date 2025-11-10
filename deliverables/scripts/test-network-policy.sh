#!/bin/bash

# Network Policy Management Script
# This script allows you to block, allow, or test network policies for API-DB connections
#
# Usage:
#   ./test-network-policy.sh block    - Block API from connecting to database
#   ./test-network-policy.sh allow    - Allow API to connect to database
#   ./test-network-policy.sh test     - Run full test sequence (block -> allow)
#   ./test-network-policy.sh status   - Show current network policy status
#   ./test-network-policy.sh cleanup  - Remove all demo network policies

set -e

NAMESPACE="student-api"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Show usage
show_usage() {
    echo "Network Policy Management Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  block    - Block API from connecting to database"
    echo "  allow    - Allow API to connect to database"
    echo "  test     - Run full test sequence (baseline -> block -> allow)"
    echo "  status   - Show current network policy status"
    echo "  cleanup  - Remove all demo network policies"
    echo ""
    exit 1
}

# Check if kubectl is available
check_prerequisites() {
    if ! command -v kubectl &> /dev/null; then
        echo_error "kubectl is not installed or not in PATH"
        exit 1
    fi

    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo_error "Namespace '$NAMESPACE' does not exist"
        exit 1
    fi
}

# Get API pod name
get_api_pod() {
    API_POD=$(kubectl get pods -n "$NAMESPACE" -l app=student-crud-api-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$API_POD" ]; then
        echo_error "API pod not found. Please ensure the API is deployed."
        exit 1
    fi
    
    echo_info "Found API pod: $API_POD"
}

# Function to install curl in the pod
install_curl() {
    local pod=$1
    echo_info "Installing curl in pod (if not already available)..."
    
    kubectl exec -n "$NAMESPACE" "$pod" --container api -- sh -c "
        if command -v curl >/dev/null 2>&1; then
            echo 'curl already available'
        elif command -v apk >/dev/null 2>&1; then
            apk add --no-cache curl 2>&1
        elif command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq && apt-get install -y -qq curl 2>&1
        else
            echo 'ERROR: No package manager found'
            exit 1
        fi
    " 2>/dev/null || echo_warn "Failed to install curl, will try alternative methods"
}

# Function to test API database-dependent endpoint
test_api_db_endpoint() {
    local pod=$1
    local expected_status=$2
    local description=$3
    
    echo_info "Testing API database endpoint ($description)..."
    
    response=$(kubectl exec -n "$NAMESPACE" "$pod" --container api -- sh -c 'curl -s --max-time 5 http://localhost:3000/api/v1/students 2>&1' 2>/dev/null || echo "ERROR:curl_failed")
    response=$(echo "$response" | grep -v "Defaulted container" | head -1)
    
    if echo "$response" | grep -q "\[.*\]\|200\|students" && [ "$expected_status" == "success" ]; then
        echo_info "✓ API database endpoint check passed"
        return 0
    elif echo "$response" | grep -q "ERROR\|timeout\|Connection refused\|ECONNREFUSED\|curl_failed\|getaddrinfo\|database\|connection" && [ "$expected_status" == "failure" ]; then
        echo_info "✓ API database endpoint check failed (as expected - network policy blocking)"
        return 0
    elif [ "$expected_status" == "success" ]; then
        echo_error "✗ API database endpoint check failed (unexpected)"
        echo "Response: $response"
        return 1
    else
        echo_error "✗ API database endpoint check succeeded (unexpected - should be blocked)"
        echo "Response: $response"
        return 1
    fi
}

# Function to test database connectivity from API pod
test_db_connectivity() {
    local pod=$1
    local expected_status=$2
    local description=$3
    
    echo_info "Testing database connectivity ($description)..."
    
    DB_SERVICE=$(kubectl get svc -n "$NAMESPACE" -l app.name=student-api-student-crud-api-api-db -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$DB_SERVICE" ]; then
        echo_warn "DB service not found, skipping direct DB connectivity test"
        return 0
    fi
    
    result=$(kubectl exec -n "$NAMESPACE" "$pod" --container api -- node -e "
        const net = require('net');
        const client = net.createConnection({host: '$DB_SERVICE', port: 5432}, () => {
            console.log('CONNECTION:success');
            client.end();
        });
        client.on('error', (err) => {
            console.log('CONNECTION:failed - ' + err.message);
        });
        client.setTimeout(5000, () => {
            client.destroy();
            console.log('CONNECTION:timeout');
        });
    " 2>/dev/null || echo "CONNECTION:execution_failed")
    
    if echo "$result" | grep -q "CONNECTION:success" && [ "$expected_status" == "success" ]; then
        echo_info "✓ Database connection successful"
        return 0
    elif echo "$result" | grep -q "CONNECTION:failed\|CONNECTION:timeout\|CONNECTION:execution_failed" && [ "$expected_status" == "failure" ]; then
        echo_info "✓ Database connection failed (as expected - network policy blocking)"
        return 0
    elif [ "$expected_status" == "success" ]; then
        echo_error "✗ Database connection failed (unexpected)"
        echo "Result: $result"
        return 1
    else
        echo_error "✗ Database connection succeeded (unexpected - should be blocked)"
        echo "Result: $result"
        return 1
    fi
}

# Apply blocking network policy
apply_block_policy() {
    echo_info "Applying blocking network policy..."
    
    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-api-db-connection
  namespace: $NAMESPACE
spec:
  podSelector:
    matchLabels:
      app: student-crud-api-api
  policyTypes:
  - Egress
  egress:
  # Only allow DNS, but NOT database connection
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
  # Explicitly deny database connection (no rule for port 5432)
EOF

    echo_info "Waiting for policy to take effect..."
    sleep 5
    
    if kubectl get networkpolicy -n "$NAMESPACE" block-api-db-connection &> /dev/null; then
        echo_info "✓ Blocking policy applied successfully"
        return 0
    else
        echo_error "✗ Failed to apply blocking policy"
        return 1
    fi
}

# Apply allowing network policy
apply_allow_policy() {
    echo_info "Applying allowing network policy..."
    
    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-db-connection
  namespace: $NAMESPACE
spec:
  podSelector:
    matchLabels:
      app: student-crud-api-api
  policyTypes:
  - Egress
  egress:
  # Allow DNS
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
  # Allow database connection
  - to:
    - podSelector:
        matchLabels:
          app.name: student-api-student-crud-api-api-db
    ports:
    - protocol: TCP
      port: 5432
EOF

    echo_info "Waiting for policy to take effect..."
    sleep 5
    
    if kubectl get networkpolicy -n "$NAMESPACE" allow-api-db-connection &> /dev/null; then
        echo_info "✓ Allowing policy applied successfully"
        return 0
    else
        echo_error "✗ Failed to apply allowing policy"
        return 1
    fi
}

# Remove blocking policy
remove_block_policy() {
    if kubectl get networkpolicy -n "$NAMESPACE" block-api-db-connection &> /dev/null; then
        echo_info "Removing blocking policy..."
        kubectl delete networkpolicy -n "$NAMESPACE" block-api-db-connection
        sleep 2
    fi
}

# Remove allowing policy
remove_allow_policy() {
    if kubectl get networkpolicy -n "$NAMESPACE" allow-api-db-connection &> /dev/null; then
        echo_info "Removing allowing policy..."
        kubectl delete networkpolicy -n "$NAMESPACE" allow-api-db-connection
        sleep 2
    fi
}

# Show network policy status
show_status() {
    echo_info "Network Policy Status in namespace '$NAMESPACE':"
    echo ""
    
    POLICIES=$(kubectl get networkpolicy -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$POLICIES" ]; then
        echo_info "No network policies found in namespace '$NAMESPACE'"
        echo_info "API can connect to database (default behavior)"
    else
        kubectl get networkpolicy -n "$NAMESPACE"
        echo ""
        
        for policy in $POLICIES; do
            if [ "$policy" == "block-api-db-connection" ]; then
                echo_warn "⚠ Blocking policy is active - API cannot connect to database"
            elif [ "$policy" == "allow-api-db-connection" ]; then
                echo_info "✓ Allowing policy is active - API can connect to database"
            fi
        done
    fi
}

# Cleanup all demo policies
cleanup() {
    echo_info "Cleaning up network policies..."
    remove_block_policy
    remove_allow_policy
    echo_info "✓ Cleanup complete"
}

# Command: block
cmd_block() {
    check_prerequisites
    get_api_pod
    
    remove_allow_policy
    apply_block_policy
    
    echo_info "Waiting for policy to take full effect..."
    sleep 10
    
    echo_info "Testing connectivity..."
    install_curl "$API_POD"
    test_api_db_endpoint "$API_POD" "failure" "with blocking policy"
    test_db_connectivity "$API_POD" "failure" "with blocking policy"
    
    echo ""
    echo_info "✓ API-DB connection is now blocked"
}

# Command: allow
cmd_allow() {
    check_prerequisites
    get_api_pod
    
    remove_block_policy
    apply_allow_policy
    
    echo_info "Waiting for policy to take full effect..."
    sleep 10
    
    echo_info "Testing connectivity..."
    install_curl "$API_POD"
    test_api_db_endpoint "$API_POD" "success" "with allowing policy"
    test_db_connectivity "$API_POD" "success" "with allowing policy"
    
    echo ""
    echo_info "✓ API-DB connection is now allowed"
}

# Command: test (full test sequence)
cmd_test() {
    check_prerequisites
    get_api_pod
    
    echo ""
    echo_info "========================================="
    echo_info "Network Policy Test Sequence"
    echo_info "========================================="
    echo ""
    
    # Cleanup existing policies
    remove_block_policy
    remove_allow_policy
    
    # Step 1: Baseline
    echo_info "STEP 1: Baseline Test (Before Policy)"
    echo_info "========================================="
    kubectl wait --for=condition=ready pod/"$API_POD" -n "$NAMESPACE" --timeout=60s || true
    sleep 2
    install_curl "$API_POD"
    test_api_db_endpoint "$API_POD" "success" "baseline (should work)"
    test_db_connectivity "$API_POD" "success" "baseline (should work)"
    
    # Step 2: Block
    echo ""
    echo_info "STEP 2: Apply Blocking Policy"
    echo_info "========================================="
    apply_block_policy
    echo_info "Waiting for CNI to apply network policy..."
    sleep 10
    test_api_db_endpoint "$API_POD" "failure" "with blocking policy (should fail)"
    test_db_connectivity "$API_POD" "failure" "with blocking policy (should fail)"
    
    # Step 3: Allow
    echo ""
    echo_info "STEP 3: Apply Allowing Policy"
    echo_info "========================================="
    remove_block_policy
    apply_allow_policy
    echo_info "Waiting for CNI to apply network policy..."
    sleep 10
    test_api_db_endpoint "$API_POD" "success" "with allowing policy (should work)"
    test_db_connectivity "$API_POD" "success" "with allowing policy (should work)"
    
    # Summary
    echo ""
    echo_info "========================================="
    echo_info "TEST SUMMARY"
    echo_info "========================================="
    echo ""
    echo_info "✓ Network policy test completed successfully!"
    echo ""
    show_status
}

# Main script logic
if [ $# -eq 0 ]; then
    show_usage
fi

COMMAND=$1

case "$COMMAND" in
    block)
        cmd_block
        ;;
    allow)
        cmd_allow
        ;;
    test)
        cmd_test
        ;;
    status)
        check_prerequisites
        show_status
        ;;
    cleanup)
        check_prerequisites
        cleanup
        ;;
    *)
        echo_error "Unknown command: $COMMAND"
        echo ""
        show_usage
        ;;
esac

