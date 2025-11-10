# Stage 1: Generate config
FROM node:20-alpine AS config-builder

WORKDIR /app

# Copy config generation script
COPY generate-config.js .

# Generate config.js from environment variable (default if not set)
ARG API_BASE_URL=http://localhost:3000/api/v1
ENV REACT_APP_API_URL=${API_BASE_URL}

RUN node generate-config.js

# Stage 2: Serve with nginx
FROM nginx:alpine

# Install node for runtime config generation
RUN apk add --no-cache nodejs

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy frontend files
COPY index.html /usr/share/nginx/html/
COPY styles.css /usr/share/nginx/html/
COPY app.js /usr/share/nginx/html/
COPY generate-config.js /usr/share/nginx/html/

# Copy startup script
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Copy default config (will be regenerated at runtime if env var is set)
COPY --from=config-builder /app/config.js /usr/share/nginx/html/config.js

# Expose port 8080
EXPOSE 8080

# Use custom entrypoint
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]

