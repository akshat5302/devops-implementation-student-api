#!/bin/sh

# Generate config.js from environment variable if provided
if [ -n "$API_BASE_URL" ]; then
  echo "Generating config.js with API_BASE_URL=$API_BASE_URL"
  cd /usr/share/nginx/html
  REACT_APP_API_URL="$API_BASE_URL" node generate-config.js
fi

# API Connectivity Check (optional, for testing failure scenarios)
if [ "${CHECK_API_CONNECTIVITY:-false}" = "true" ]; then
  echo "Checking API connectivity to $API_BASE_URL..."
  
  # Extract host and port from API_BASE_URL
  API_HOST=$(echo "$API_BASE_URL" | sed -E 's|https?://([^:/]+).*|\1|')
  API_PORT=$(echo "$API_BASE_URL" | sed -E 's|https?://[^:]+:([0-9]+).*|\1|' || echo "80")
  
  # Default port based on protocol
  if echo "$API_BASE_URL" | grep -q "^https"; then
    API_PORT="${API_PORT:-443}"
  else
    API_PORT="${API_PORT:-80}"
  fi
  
  RETRIES=${API_CHECK_RETRIES:-3}
  DELAY=${API_CHECK_DELAY:-2}
  ATTEMPT=1
  
  while [ $ATTEMPT -le $RETRIES ]; do
    echo "Attempt $ATTEMPT/$RETRIES: Checking $API_HOST:$API_PORT..."
    
    # Try to connect using netcat or curl
    if command -v nc >/dev/null 2>&1; then
      if nc -z -w 2 "$API_HOST" "$API_PORT" 2>/dev/null; then
        echo "✅ API is reachable at $API_HOST:$API_PORT"
        break
      fi
    elif command -v curl >/dev/null 2>&1; then
      if curl -f -s -m 2 "$API_BASE_URL/health" >/dev/null 2>&1 || curl -f -s -m 2 "$API_BASE_URL" >/dev/null 2>&1; then
        echo "✅ API is reachable at $API_BASE_URL"
        break
      fi
    else
      echo "⚠️  No network tools available (nc/curl), skipping connectivity check"
      break
    fi
    
    if [ $ATTEMPT -lt $RETRIES ]; then
      echo "❌ API check failed (attempt $ATTEMPT/$RETRIES), retrying in ${DELAY}s..."
      sleep $DELAY
    else
      echo "❌ API is NOT reachable at $API_BASE_URL after $RETRIES attempts"
      if [ "${FAIL_ON_API_UNREACHABLE:-false}" = "true" ]; then
        echo "🚨 FAIL_ON_API_UNREACHABLE is true - exiting container"
        exit 1
      else
        echo "⚠️  Frontend will start but API calls will fail"
      fi
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
  done
fi

# Start nginx
exec "$@"
