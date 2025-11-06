# SRE Implementation Deliverables

This directory contains all deliverables for the SRE implementation of the Student API application.

## Directory Structure

```
deliverables/
├── README.md                          # This file
├── SRE-REPORT.md                      # Comprehensive SRE implementation report
├── grafana-dashboards/
│   └── student-api-dashboard.json     # Grafana dashboard for application metrics
├── prometheus-alerts/
│   └── student-api-alerts.yaml        # Prometheus alert rules
└── scripts/
    ├── setup-cluster.sh               # Automated cluster setup script
    ├── troubleshoot.sh                # Troubleshooting and diagnostic script
    └── verify-deployment.sh           # Deployment verification script
```

## Quick Start

### 1. Setup Cluster
```bash
./deliverables/scripts/setup-cluster.sh
```

### 2. Verify Deployment
```bash
./deliverables/scripts/verify-deployment.sh
```

### 3. Troubleshoot Issues
```bash
./deliverables/scripts/troubleshoot.sh
```

## Files Description

### SRE-REPORT.md
Comprehensive report documenting:
- Issues identified and root causes
- Fixes implemented
- Configuration changes
- Verification steps
- Before/after comparison
- Future improvements

### Grafana Dashboard
**File:** `grafana-dashboards/student-api-dashboard.json`

**Import Instructions:**
1. Access Grafana UI (port-forward to port 3000)
2. Navigate to Dashboards → Import
3. Upload the JSON file or paste its contents
4. Configure data source (Prometheus)

**Dashboard Panels:**
- HTTP Request Rate
- HTTP Error Rate
- Request Latency (p50, p90, p95, p99)
- Active Requests
- Database Query Duration
- Database Connection Count
- Database Errors
- Pod CPU Usage
- Pod Memory Usage
- Pod Restart Count

### Prometheus Alerts
**File:** `prometheus-alerts/student-api-alerts.yaml`

**Installation:**
```bash
# Create PrometheusRule resource
kubectl apply -f deliverables/prometheus-alerts/student-api-alerts.yaml -n monitoring
```

**Alerts Configured:**
- High HTTP Error Rate
- High Latency (p90, p95, p99)
- Database Errors
- High Database Connections
- High Pod CPU/Memory Usage
- Pod CrashLoopBackOff
- Pod Not Ready
- High Restart Count
- Service Endpoints Down
- Slow Database Queries

### Scripts

#### setup-cluster.sh
Automated script to:
- Create multi-node Minikube cluster
- Label and taint nodes appropriately
- Create namespaces
- Install monitoring stack
- Deploy application

**Usage:**
```bash
chmod +x deliverables/scripts/setup-cluster.sh
./deliverables/scripts/setup-cluster.sh
```

#### troubleshoot.sh
Diagnostic script that checks:
- Pod status and health
- Service endpoints
- Pod logs
- Recent events
- Resource usage
- Network policies
- HPA status
- Ingress configuration
- Database connectivity
- Health endpoints
- Monitoring stack status

**Usage:**
```bash
chmod +x deliverables/scripts/troubleshoot.sh
./deliverables/scripts/troubleshoot.sh
```

#### verify-deployment.sh
Verification script that validates:
- Namespace existence
- Pod status (Running and Ready)
- Service endpoints
- Health endpoint responses
- Database connectivity
- API endpoint functionality
- Metrics endpoint
- HPA configuration
- Ingress resources
- Resource limits
- Health probes

**Usage:**
```bash
chmod +x deliverables/scripts/verify-deployment.sh
./deliverables/scripts/verify-deployment.sh
```

## Configuration Changes

### Modified Helm Chart Files
All changes are in the `charts/crud-api/` directory:

1. **values.yaml** - Added:
   - Resource limits and requests for all components
   - Health probe configurations
   - Autoscaling configurations
   - Network policy flag

2. **templates/api-deployment.yaml** - Added:
   - Container ports
   - Resource limits
   - Liveness and readiness probes

3. **templates/frontend-deployment.yaml** - Added:
   - Liveness and readiness probes

4. **templates/api-db-statefulset.yaml** - Added:
   - Container ports
   - Resource limits
   - Liveness and readiness probes

### New Helm Chart Files
1. **templates/api-hpa.yaml** - Horizontal Pod Autoscaler for API
2. **templates/frontend-hpa.yaml** - Horizontal Pod Autoscaler for Frontend
3. **templates/network-policy.yaml** - Network policies for all components

## Verification Evidence

### Pod Status
```bash
kubectl get pods -n student-api
```
Expected: All pods in `Running` state with `1/1` or `2/2` ready status

### Service Endpoints
```bash
kubectl get svc,endpoints -n student-api
```
Expected: All services have active endpoints

### Health Check
```bash
API_POD=$(kubectl get pods -n student-api -l app=student-crud-api-api -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n student-api $API_POD -- wget -qO- http://localhost:3000/api/v1/health
```
Expected: Returns healthy status

### API Test
```bash
kubectl exec -n student-api $API_POD -- wget -qO- http://localhost:3000/api/v1/students
```
Expected: Returns student list (may be empty array)

### HPA Status
```bash
kubectl get hpa -n student-api
```
Expected: HPAs created and showing current/target metrics

## Accessing Services

### Grafana
```bash
kubectl port-forward svc/observability-grafana 3000:80 -n monitoring
```
Access at: http://localhost:3000

### Prometheus
```bash
kubectl port-forward svc/observability-kube-prometheus-stack-prometheus 9090:9090 -n monitoring
```
Access at: http://localhost:9090

### API (via Port Forward)
```bash
kubectl port-forward svc/student-crud-api-api 3000:3000 -n student-api
```
Access at: http://localhost:3000

### Frontend (via Port Forward)
```bash
kubectl port-forward svc/student-crud-api-frontend 8080:8080 -n student-api
```
Access at: http://localhost:8080

## Troubleshooting

### Common Issues

1. **Pods in CrashLoopBackOff**
   - Check logs: `kubectl logs <pod-name> -n student-api`
   - Check events: `kubectl describe pod <pod-name> -n student-api`
   - Verify resource limits are appropriate

2. **Service has no endpoints**
   - Check pod labels match service selector
   - Verify pods are in Ready state
   - Check network policies if enabled

3. **Database connection issues**
   - Verify database pod is running
   - Check network policies allow traffic
   - Verify database credentials in secrets

4. **High resource usage**
   - Check current usage: `kubectl top pods -n student-api`
   - Review HPA configuration
   - Consider increasing resource limits

5. **Health probes failing**
   - Verify health endpoint is accessible
   - Check probe configuration
   - Review pod logs for errors

## Next Steps

1. **Enable Network Policies** (when ready):
   ```yaml
   # In values.yaml
   networkPolicy:
     enabled: true
   ```

2. **Import Grafana Dashboard**:
   - Use the provided JSON file
   - Configure Prometheus data source

3. **Apply Prometheus Alerts**:
   ```bash
   kubectl apply -f deliverables/prometheus-alerts/student-api-alerts.yaml -n monitoring
   ```

4. **Monitor and Tune**:
   - Review metrics and adjust thresholds
   - Fine-tune HPA based on actual usage
   - Optimize resource limits based on observed usage

## Support

For issues or questions:
1. Review the SRE-REPORT.md for detailed information
2. Run the troubleshoot.sh script for diagnostics
3. Check pod logs and events
4. Review Grafana dashboards for metrics

## License

This implementation is part of the Student API project and follows the same license terms.

