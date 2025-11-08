#!/bin/bash

# Script to test frontend failure scenarios by toggling faulty variables
# Usage:
#   ./test-frontend-failure.sh enable   - Deploy with faulty config (triggers CrashLoopBackOff)
#   ./test-frontend-failure.sh disable  - Deploy with correct config (fixes the issue)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALUES_FILE="$PROJECT_ROOT/charts/crud-api/values.yaml"
NAMESPACE="student-api"
RELEASE_NAME="student-crud-api"

ACTION="${1:-help}"

case "$ACTION" in
  enable)
    echo "🔴 Enabling faulty frontend configuration to trigger CrashLoopBackOff..."
    
    # Check if already enabled
    if grep -q "# FAULTY_CONFIG_ENABLED" "$VALUES_FILE"; then
      echo "⚠️  Faulty config already enabled. Disable it first with: ./test-frontend-failure.sh disable"
      exit 1
    fi
    
    # Add/Update faulty configuration
    # Use wrong API URL that will cause connectivity failures
    # Enable connectivity check and fail on unreachable to trigger CrashLoopBackOff
    
    # Check if apiUrl exists, if so update it, otherwise add it
    if grep -q "^  apiUrl:" "$VALUES_FILE"; then
      sed -i.bak 's|^  apiUrl:.*|  apiUrl: "http://wrong-backend-url:3000/api/v1"  # Wrong URL to trigger failures|' "$VALUES_FILE"
    else
      sed -i.bak '/^frontend:/a\
  # FAULTY_CONFIG_ENABLED - Added by test-frontend-failure.sh\
  apiUrl: "http://wrong-backend-url:3000/api/v1"  # Wrong URL to trigger failures
' "$VALUES_FILE"
    fi
    
    # Update or add checkApiConnectivity
    if grep -q "^  checkApiConnectivity:" "$VALUES_FILE"; then
      sed -i.bak 's|^  checkApiConnectivity:.*|  checkApiConnectivity: true  # Enable connectivity check|' "$VALUES_FILE"
    else
      sed -i.bak '/^  apiUrl:.*wrong-backend-url/a\
  checkApiConnectivity: true  # Enable connectivity check
' "$VALUES_FILE"
    fi
    
    # Update or add failOnApiUnreachable
    if grep -q "^  failOnApiUnreachable:" "$VALUES_FILE"; then
      sed -i.bak 's|^  failOnApiUnreachable:.*|  failOnApiUnreachable: true  # Exit container if API is unreachable (triggers CrashLoopBackOff)|' "$VALUES_FILE"
    else
      sed -i.bak '/^  checkApiConnectivity: true/a\
  failOnApiUnreachable: true  # Exit container if API is unreachable (triggers CrashLoopBackOff)
' "$VALUES_FILE"
    fi
    
    # Add marker if not present
    if ! grep -q "# FAULTY_CONFIG_ENABLED" "$VALUES_FILE"; then
      sed -i.bak '/^  apiUrl:.*wrong-backend-url/i\
  # FAULTY_CONFIG_ENABLED - Added by test-frontend-failure.sh
' "$VALUES_FILE"
    fi
    
    echo "✅ Added faulty API URL configuration"
    echo "📦 Deploying with faulty configuration..."
    
    helm upgrade "$RELEASE_NAME" "$PROJECT_ROOT/charts/crud-api" \
      -f "$VALUES_FILE" \
      -n "$NAMESPACE" \
      --wait --timeout=5m
    
    echo ""
    echo "🔴 Frontend is now configured with faulty API URL"
    echo "   This will cause CrashLoopBackOff if connectivity checks are enabled"
    echo "   Or API calls will fail if connectivity checks are disabled"
    echo ""
    echo "📊 Monitor with: kubectl get pods -n $NAMESPACE -l app.kubernetes.io/component=frontend -w"
    echo "🔍 Check logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=frontend --tail=50"
    ;;
    
  disable)
    echo "🟢 Disabling faulty frontend configuration..."
    
    # Remove faulty configuration marker
    if grep -q "# FAULTY_CONFIG_ENABLED" "$VALUES_FILE"; then
      sed -i.bak '/# FAULTY_CONFIG_ENABLED/d' "$VALUES_FILE"
    fi
    
    # Restore apiUrl to default (empty will use ingress.api)
    if grep -q "apiUrl: \"http://wrong-backend-url" "$VALUES_FILE"; then
      sed -i.bak 's|apiUrl: "http://wrong-backend-url.*|apiUrl: "" # If empty, will use http://student-api.atlan.com/api/v1|' "$VALUES_FILE"
    fi
    
    # Restore connectivity checks to default (disabled)
    if grep -q "^  checkApiConnectivity:" "$VALUES_FILE"; then
      sed -i.bak 's|^  checkApiConnectivity:.*|  checkApiConnectivity: false # Enable API connectivity check at startup (for testing failures)|' "$VALUES_FILE"
    fi
    
    if grep -q "^  failOnApiUnreachable:" "$VALUES_FILE"; then
      sed -i.bak 's|^  failOnApiUnreachable:.*|  failOnApiUnreachable: false # Exit container if API is unreachable (causes CrashLoopBackOff when enabled)|' "$VALUES_FILE"
    fi
    
    echo "✅ Restored default configuration (connectivity checks disabled)"
    
    echo "📦 Deploying with correct configuration..."
    
    helm upgrade "$RELEASE_NAME" "$PROJECT_ROOT/charts/crud-api" \
      -f "$VALUES_FILE" \
      -n "$NAMESPACE" \
      --wait --timeout=5m
    
    echo ""
    echo "🟢 Frontend is now configured with correct API URL"
    echo "   Pods should recover and start successfully"
    echo ""
    echo "📊 Monitor with: kubectl get pods -n $NAMESPACE -l app.kubernetes.io/component=frontend -w"
    ;;
    
  status)
    echo "📊 Current frontend configuration status:"
    echo ""
    
    if grep -q "# FAULTY_CONFIG_ENABLED" "$VALUES_FILE"; then
      echo "🔴 Status: FAULTY CONFIG ENABLED"
      echo "   Frontend is configured with wrong API URL"
      grep -A 1 "# FAULTY_CONFIG_ENABLED" "$VALUES_FILE" | grep "apiUrl:"
    else
      echo "🟢 Status: NORMAL CONFIG"
      echo "   Frontend is configured with correct API URL"
      grep "apiUrl:" "$VALUES_FILE" | head -1
    fi
    
    echo ""
    echo "📦 Pod status:"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=frontend 2>/dev/null || echo "No frontend pods found"
    ;;
    
  help|--help|-h)
    echo "Frontend Failure Testing Script"
    echo ""
    echo "Usage: $0 [enable|disable|status]"
    echo ""
    echo "Commands:"
    echo "  enable   - Deploy frontend with faulty API URL (triggers failures)"
    echo "  disable  - Deploy frontend with correct API URL (fixes the issue)"
    echo "  status   - Show current configuration and pod status"
    echo ""
    echo "Examples:"
    echo "  $0 enable   # Trigger CrashLoopBackOff for testing alerts"
    echo "  $0 disable  # Fix the issue and recover pods"
    echo "  $0 status   # Check current state"
    ;;
    
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Run '$0 help' for usage information"
    exit 1
    ;;
esac

# Clean up backup files
if [ -f "$VALUES_FILE.bak" ]; then
  rm -f "$VALUES_FILE.bak"
fi

