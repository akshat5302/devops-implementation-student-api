# Alert Testing Guide

This document describes how to test all Prometheus alerts configured for the Student API.

## ⚠️ Important: Rebuild Required

**Before testing alerts, you must rebuild the Docker image** to include the test endpoints and metric fixes:

```bash
# Build new image
TAG=test-alerts
docker build --no-cache -t akshat5302/student-crud-api:${TAG} .

# Load into minikube (if using minikube)
docker save akshat5302/student-crud-api:${TAG} | minikube image load -

# Update Helm values
# Edit charts/crud-api/values.yaml: api.image.tag = "test-alerts"

# Upgrade deployment
helm upgrade student-crud-api charts/crud-api -n student-api -f charts/crud-api/values.yaml

# Or use the automated script
./deliverables/scripts/rebuild-and-deploy.sh
```

## Overview

The Student API includes test endpoints that can trigger various alert conditions. These endpoints are designed for testing and should **NOT** be exposed in production environments.

## Test Endpoints

### Base URL
- Local: `http://localhost:3000/api/v1/test`
- Kubernetes: `http://student-api.atlan.com/api/v1/test`

### Available Test Endpoints

#### 1. `/trigger-alerts?alertType=<type>`
Triggers specific alert conditions based on the `alertType` parameter.

**Available Alert Types:**

- `high-error-rate` - Triggers HTTP 500 errors
- `high-latency` - Triggers slow responses (default 6s, configurable via `delay` param)
- `database-error` - Triggers database errors
- `high-db-connections` - Creates many database connections (>50)
- `slow-db-query` - Executes slow database queries (default 2s, configurable via `delay` param)
- `cpu-intensive` - Performs CPU-intensive calculations
- `memory-intensive` - Allocates large amounts of memory
- `crash` - Crashes the pod (use with caution!)

**Example:**
```bash
# Trigger high latency
curl "http://localhost:3000/api/v1/test/trigger-alerts?alertType=high-latency&delay=6000"

# Trigger database errors
curl "http://localhost:3000/api/v1/test/trigger-alerts?alertType=database-error"

# Trigger CPU-intensive operation
curl "http://localhost:3000/api/v1/test/trigger-alerts?alertType=cpu-intensive&iterations=100000000"
```

#### 2. `/trigger-errors?count=<n>&status=<code>`
Rapidly triggers multiple HTTP errors.

**Parameters:**
- `count` - Number of errors to trigger (default: 10)
- `status` - HTTP status code (default: 500)

**Example:**
```bash
# Trigger 50 errors with 500 status
curl "http://localhost:3000/api/v1/test/trigger-errors?count=50&status=500"
```

#### 3. `/trigger-slow-requests?delay=<ms>`
Triggers slow HTTP requests.

**Parameters:**
- `delay` - Delay in milliseconds (default: 3000)

**Example:**
```bash
# Trigger slow request (3 seconds)
curl "http://localhost:3000/api/v1/test/trigger-slow-requests?delay=3000"
```

## Alert Testing Script

A bash script is provided to automate alert testing:

```bash
./deliverables/scripts/test-alerts.sh
```

The script will:
1. Trigger multiple alert conditions
2. Provide instructions for manual testing
3. Show how to verify alerts in Prometheus/Grafana

## Testing Each Alert

### 1. High HTTP Error Rate
**Alert:** `HighHTTPErrorRate`  
**Threshold:** > 0.1 errors/sec for 5 minutes

```bash
# Trigger 50 errors over 6 minutes (exceeds threshold)
for i in {1..50}; do
  curl "http://localhost:3000/api/v1/test/trigger-errors?status=500" &
  sleep 7
done
```

**Verify:**
```bash
# Check error rate in Prometheus
rate(http_errors_total{application="student-api"}[5m])
```

### 2. High Latency Alerts
**Alerts:** `HighP90Latency`, `HighP95Latency`, `HighP99Latency`  
**Thresholds:** P90 > 1s, P95 > 2s, P99 > 5s for 5 minutes

```bash
# Trigger P90 latency (> 1s)
curl "http://localhost:3000/api/v1/test/trigger-alerts?alertType=high-latency&delay=1500"

# Trigger P95 latency (> 2s)
curl "http://localhost:3000/api/v1/test/trigger-alerts?alertType=high-latency&delay=2500"

# Trigger P99 latency (> 5s)
curl "http://localhost:3000/api/v1/test/trigger-alerts?alertType=high-latency&delay=6000"
```

**Verify:**
```bash
# Check latency percentiles
histogram_quantile(0.90, rate(http_request_duration_seconds_bucket{application="student-api"}[5m]))
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{application="student-api"}[5m]))
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{application="student-api"}[5m]))
```

### 3. Database Errors
**Alert:** `DatabaseErrors`  
**Threshold:** > 0.05 errors/sec for 5 minutes

```bash
# Trigger database errors
for i in {1..20}; do
  curl "http://localhost:3000/api/v1/test/trigger-alerts?alertType=database-error" &
  sleep 3
done
```

**Verify:**
```bash
# Check database error rate
rate(db_error_total{application="student-api"}[5m])
```

### 4. High Database Connections
**Alert:** `HighDatabaseConnections`  
**Threshold:** > 50 connections for 5 minutes

```bash
# Trigger high connection count
curl "http://localhost:3000/api/v1/test/trigger-alerts?alertType=high-db-connections"
```

**Verify:**
```bash
# Check connection count
db_connection_count{application="student-api"}
```

### 5. Slow Database Queries
**Alert:** `SlowDatabaseQueries`  
**Threshold:** P95 > 1s for 10 minutes

```bash
# Trigger slow queries
for i in {1..10}; do
  curl "http://localhost:3000/api/v1/test/trigger-alerts?alertType=slow-db-query&delay=2000" &
  sleep 5
done
```

**Verify:**
```bash
# Check query duration
histogram_quantile(0.95, rate(db_query_duration_seconds_bucket{application="student-api"}[5m]))
```

### 6. High CPU Usage
**Alert:** `HighPodCPUUsage`  
**Threshold:** > 80% CPU for 10 minutes

```bash
# Trigger CPU-intensive operations
curl "http://localhost:3000/api/v1/test/trigger-alerts?alertType=cpu-intensive&iterations=100000000" &
curl "http://localhost:3000/api/v1/test/trigger-alerts?alertType=cpu-intensive&iterations=100000000" &
curl "http://localhost:3000/api/v1/test/trigger-alerts?alertType=cpu-intensive&iterations=100000000" &
```

**Verify:**
```bash
# Check CPU usage
rate(container_cpu_usage_seconds_total{pod=~"student-crud-api-api-.*"}[5m]) * 100
```

### 7. High Memory Usage
**Alert:** `HighPodMemoryUsage`  
**Threshold:** > 85% memory for 10 minutes

```bash
# Trigger memory-intensive operation
curl "http://localhost:3000/api/v1/test/trigger-alerts?alertType=memory-intensive&size=10000000"
```

**Verify:**
```bash
# Check memory usage
(container_memory_working_set_bytes{pod=~"student-crud-api-api-.*"} / container_spec_memory_limit_bytes{pod=~"student-crud-api-api-.*"}) * 100
```

### 8. Pod CrashLoopBackOff
**Alert:** `PodCrashLoopBackOff`  
**Threshold:** Pod in CrashLoopBackOff for 5 minutes

```bash
# WARNING: This will crash the pod!
curl "http://localhost:3000/api/v1/test/trigger-alerts?alertType=crash"
```

**Verify:**
```bash
# Check pod status
kubectl get pods -n student-api -l app=student-crud-api-api
kubectl describe pod <pod-name> -n student-api
```

### 9. Pod Not Ready
**Alert:** `PodNotReady`  
**Threshold:** Pod not Running for 10 minutes

```bash
# Scale down deployment
kubectl scale deployment student-crud-api-api -n student-api --replicas=0

# Wait 10 minutes, then scale back up
kubectl scale deployment student-crud-api-api -n student-api --replicas=1
```

### 10. High Pod Restart Count
**Alert:** `HighPodRestartCount`  
**Threshold:** > 5 restarts in 1 hour

```bash
# Manually restart pod multiple times
for i in {1..6}; do
  kubectl delete pod -n student-api -l app=student-crud-api-api
  sleep 60
done
```

### 11. Service Endpoints Down
**Alert:** `ServiceEndpointsDown`  
**Threshold:** No endpoints available for 5 minutes

```bash
# Scale down deployment
kubectl scale deployment student-crud-api-api -n student-api --replicas=0

# Wait 5 minutes, then scale back up
kubectl scale deployment student-crud-api-api -n student-api --replicas=1
```

**Verify:**
```bash
# Check endpoints
kubectl get endpoints -n student-api
```

## Viewing Alerts

### In Prometheus
```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/observability-kube-prometh-prometheus 9090:9090

# Open http://localhost:9090/alerts
```

### In Grafana
```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/observability-grafana 3000:80

# Open http://localhost:3000
# Navigate to: Alerting > Alert Rules
```

### In AlertManager
```bash
# Port-forward AlertManager
kubectl port-forward -n monitoring svc/observability-kube-prometh-alertmanager 9093:9093

# Open http://localhost:9093
```

## Verifying Metrics

Check that metrics are being exposed correctly:

```bash
# Get all metrics
curl http://localhost:3000/metrics

# Filter specific metrics
curl http://localhost:3000/metrics | grep -E "(http_errors_total|http_request_duration_seconds|db_error_total|db_connection_count)"
```

## Important Notes

1. **Production Safety:** These test endpoints should be disabled or protected in production environments.

2. **Alert Timing:** Most alerts require sustained conditions for several minutes before firing. Be patient when testing.

3. **Resource Impact:** Some test endpoints (CPU/memory intensive) can impact pod performance. Use with caution.

4. **Pod Crashes:** The crash endpoint will terminate the pod. Kubernetes will restart it automatically, but this may cause brief service disruption.

5. **Database Impact:** Database error and connection tests may impact database performance. Monitor database metrics during testing.

## Cleanup

After testing, ensure all test conditions are cleared:

```bash
# Scale deployment back to normal
kubectl scale deployment student-crud-api-api -n student-api --replicas=1

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=student-crud-api-api -n student-api --timeout=300s

# Verify metrics return to normal
curl http://localhost:3000/metrics | grep -E "(http_errors_total|db_error_total)"
```
