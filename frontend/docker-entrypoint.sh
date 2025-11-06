#!/bin/sh

# Generate config.js from environment variable if provided
if [ -n "$API_BASE_URL" ]; then
  echo "Generating config.js with API_BASE_URL=$API_BASE_URL"
  cd /usr/share/nginx/html
  REACT_APP_API_URL="$API_BASE_URL" node generate-config.js
fi

# Start nginx
exec "$@"

